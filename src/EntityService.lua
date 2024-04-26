--[[
This matches active prototypes to create a mapping between entity names
and service (group) names.

It also has a routine to re-scan the surfaces using that entity name map.
FIXME: this didn't catch all fuel-using entities (burner-inserter in vanilla)
Add back scan from GlobalState.
]]
local M = {}

--[[
-- key=entity.name, val=service_type
local name_to_service = {
  ["network-chest"]           = "network-chest",
  ["network-chest-provider"]  = "network-chest-provider",
  ["network-chest-requester"] = "network-chest-requester",
  ["network-tank"]            = "network-tank",
  ["network-tank-provider"]   = "network-tank-provider",
  ["network-tank-requester"]  = "network-tank-requester",
  ["entity-ghost"]            = "entity-ghost",
  ["tile-ghost"]              = "tile-ghost",
}

-- key=entity.type, val=service_type
local etype_to_service = {
  ["ammo-turret"]        = "general-service", -- "ammo-turret",
  ["artillery-turret"]   = "general-service", -- "artillery-turret",
  ["assembling-machine"] = "assembling-machine",
  ["car"]                = "car",
  ["locomotive"]         = "general-service",
  ["boiler"]             = "general-service",
  ["burner-generator"]   = "general-service",
  ["entity-ghost"]       = "entity-ghost",
  ["furnace"]            = "furnace",
  ["lab"]                = "lab",
  ["rocket-silo"]        = "rocket-silo",
  ["spider-vehicle"]     = "spidertron",
  ["mining-drill"]       = "general-service",
  ["reactor"]            = "reactor",
}

-- key=service, val=filter
local filter_to_service = {
  ["car"] =  { filter = "type", type = "car" },
  ["boiler"] =  { filter = "type", type = "boiler" },
  ["burner-generator"] =  { filter = "type", type = "burner-generator" },
  ["furnace"] =  { filter = "type", type = "furnace" },
  ["mining-drill"] =  { filter = "type", type = "mining-drill" },
  ["artillery-turret"] =  { filter = "type", type = "artillery-turret" },
  ["ammo-turret"] =  { filter = "type", type = "ammo-turret" },
  ["assembling-machine"] =  { filter = "type", type = "assembling-machine" },
  ["lab"] =  { filter = "type", type = "lab" },
  ["sink-chest"] = { filter = "name", name = "arr-hidden-sink-chest" },
  ["sink-tank"] = { filter = "name", name = "arr-sink-tank" },
  ["logistic-sink-chest"] = { filter = "name", name = "arr-logistic-sink-chest" },
  ["logistic-requester-chest"] = { filter = "name", name = "arr-logistic-requester-chest" },
  ["arr-requester-tank"] = { filter = "name", name = "arr-requester-tank" },
  ["spidertron"] = { filter = "type", type = "spider-vehicle" },
  ["reactor"] = { filter = "type", type = "reactor" },
  ["arr-combinator"] = { filter = "name", name = "arr-combinator" },
}

function M.calculate_groups()
  local names_to_groups = {}

  -- copy over direct name-to-service maps
  for name, service in pairs(name_to_service) do
    if game.entity_prototypes[name] ~= nil then
      names_to_groups[name] = service
    else
      print(string.format("MISSING: %s", name))
    end
  end

  -- search type-to-service maps
  for etype, service in pairs(etype_to_service) do
    local entity_prototypes = game.get_filtered_entity_prototypes({{ filter="type", type=etype }})
    for name, _ in pairs(entity_prototypes) do
      names_to_groups[name] = service
    end
  end

  -- generic filters
  for service, filter in pairs(filter_to_service) do
    local entity_prototypes = game.get_filtered_entity_prototypes({ filter })
    for name, _ in pairs(entity_prototypes) do
      names_to_groups[name] = service
    end
  end

  -- logistic chests
  local entity_prototypes = game.get_filtered_entity_prototypes({{ filter="type", type="logistic-container" }})
  for _, prot in pairs(entity_prototypes) do
    names_to_groups[prot.name] = "logistic-chest-" .. prot.logistic_mode
  end

  return names_to_groups
end
]]

--[[
Scan prototypes and calculate a mapping of entity.name to service name.
]]
function M.scan_prototypes()
  -- fixed list of mappings
  -- key=entity_name, val=service_type
  local fixed_name_to_service = {
    ["network-chest"]           = "network-chest",
    ["network-chest-provider"]  = "network-chest-provider",
    ["network-chest-requester"] = "network-chest-requester",
    ["network-tank"]            = "network-tank",
    ["network-tank-provider"]   = "network-tank-provider",
    ["network-tank-requester"]  = "network-tank-requester",
    ["entity-ghost"]            = "entity-ghost",
    ["tile-ghost"]              = "tile-ghost",
  }

  -- type to service mappings
  -- key=type, val=service_type
  local etype_to_service = {
    ["ammo-turret"]        = "general-service", -- "ammo-turret",
    ["artillery-turret"]   = "general-service", -- "artillery-turret",
    ["assembling-machine"] = "assembling-machine",
    ["car"]                = "car",
    ["entity-ghost"]       = "entity-ghost",
    ["furnace"]            = "furnace",
    ["lab"]                = "lab",
    ["rocket-silo"]        = "rocket-silo",
    ["spider-vehicle"]     = "spidertron",
    ["reactor"]            = "reactor",
  }

  local name_to_service = {}
  for name, service in pairs(fixed_name_to_service) do
    if game.entity_prototypes[name] ~= nil then
      name_to_service[name] = service
    end
  end

  for _, prot in pairs(game.entity_prototypes) do
    -- discard hidden entities and those that can't be placed by a player
    if prot.has_flag("hidden") or not prot.has_flag("player-creation") then
      -- not adding it, not sure what this skips anymore

    elseif prot.type == "logistic-container" then
      -- special handler for logistic containers
      name_to_service[prot.name] = "logistic-chest-" .. prot.logistic_mode

    else
      -- see if we handle the type
      local ss = etype_to_service[prot.type]
      if ss ~= nil then
        name_to_service[prot.name] = ss
      else
        -- check for other 'general-service'
        local svc_type
        -- check for stuff that burns chemicals (coal)
        if prot.burner_prototype ~= nil and prot.burner_prototype.fuel_categories.chemical == true then
          svc_type = "general-service" -- for refueling
          --clog("Adding %s based on burner_prototype", prot.name)
        end
        if svc_type ~= nil then
          name_to_service[prot.name] = svc_type
        end
      end
    end
  end
  log(("Servicing %s prototypes"):format(table_size(name_to_service)))
  log(serpent.block(name_to_service))
  return name_to_service
end

-- called once at startup if scan_prototypes() returns something different
function M.scan_surfaces()
  print(string.format("[%s] cheat-network: Scanning surfaces", game.tick))
  local name_filter = {}
  for name, _ in pairs(global.name_service_map) do
    table.insert(name_filter, name)
  end
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered { name = name_filter }
    for _, ent in ipairs(entities) do
      M.entity_info_add(ent)
    end
  end
  M.reset_queues()
  print(string.format("[%s] cheat-network: Scanning complete", game.tick))
end

return M
