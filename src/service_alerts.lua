--[[
Scans alerts once per second and tries to insert missing material into a
logistic constgruction network that overlaps the target.
]]
local GlobalState = require "src.GlobalState"
local Event = require('__stdlib__/stdlib/event/event')
local clog = require("src.log_console").log

--[[
This is called to handle the lack of a material.
entity is used for the unit_number and position.
]]
local function handle_missing_material(entity, missing_name, item_count)
  item_count = item_count or 1
  -- a cliff doesn't have a unit_number, so fake one based on the position
  local key = entity.unit_number
  if key == nil then
    key = string.format("%s,%s", entity.position.x, entity.position.y)
  end

  -- did we already transfer something for this ghost/upgrade?
  if GlobalState.alert_transfer_get(key) == true then
    return
  end

  -- make sure it is something we can handle
  local name, count = GlobalState.resolve_name(missing_name)
  if name == nil then
    return
  end
  count = count or item_count

  -- do we have an item to send?
  local network_count = GlobalState.get_item_count(name)
  if network_count < count then
    GlobalState.missing_item_set(name, key, count)
    return
  end

  -- Find a construction network with a construction robot that covers this position
  local nets = entity.surface.find_logistic_networks_by_construction_area(
    entity.position, "player")
  for _, net in ipairs(nets) do
    if net.all_construction_robots > 0 then
      local n_inserted = net.insert({ name = name, count = count })
      if n_inserted > 0 then
        GlobalState.increment_item_count(name, -n_inserted)
        GlobalState.alert_transfer_set(key)
        return
      end
    end
  end
end

local function service_alerts()
  GlobalState.alert_transfer_cleanup()

  -- process all the alerts for all players
  for _, player in pairs(game.players) do
    local alerts = player.get_alerts {
      type = defines.alert_type.no_material_for_construction }
    for _, xxx in pairs(alerts) do
      for _, alert_array in pairs(xxx) do
        for _, alert in ipairs(alert_array) do
          local entity = alert.target
          if entity ~= nil then
            -- we only care about ghosts and items that are set to upgrade
            if entity.name == "entity-ghost" or entity.name == "tile-ghost" then
              handle_missing_material(entity, entity.ghost_name)
            elseif entity.name == "cliff" then
              handle_missing_material(entity, "cliff-explosives")
            elseif entity.name == "item-request-proxy" then
              for k, v in pairs(entity.item_requests) do
                handle_missing_material(entity, k, v)
              end
            else
              local tent = entity.get_upgrade_target()
              if tent ~= nil then
                handle_missing_material(entity, tent.name)
              end
            end
          end
        end
      end
    end
  end

  -- send repair packs
  for _, player in pairs(game.players) do
    local alerts = player.get_alerts {
      type = defines.alert_type.not_enough_repair_packs }
    for _, xxx in pairs(alerts) do
      for _, alert_array in pairs(xxx) do
        for _, alert in ipairs(alert_array) do
          if alert.target ~= nil then
            handle_missing_material(alert.target, "repair-pack")
          end
        end
      end
    end
  end
end

Event.on_nth_tick(60, service_alerts)
