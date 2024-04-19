--[[
Scans the fluid network of a network-tank to determine the default configuration.

TODO: entity.neighbours should contain a list of connected entities.
]]
local GlobalState = require "src.GlobalState"
local constants = require "src.constants"
local clog = require("src.log_console").log

-- this is the fake metatable - all functions take an instance created via
-- network_tank_on_gui_opened() as the first parameter.
local M = {}

local debug_fluids = false

-- the default is to give/provide everything
local default_config = {
  type = "give",
  limit = 0,
  no_limit = true,
}

--[[
Check the fluidbox on the entity. We start with a network tank, so there should only be 1 fluidbox.
Search connected fluidboxes to find all filters.
That gives what the system should contain.
]]
local function search_fluid_system(entity, sysid, visited, extra_debug)
  if entity == nil or not entity.valid then
    return
  end
  local unum = entity.unit_number
  local fluidbox = entity.fluidbox
  -- visited contains [unit_number]=true, ['locked'= { names }, 'min_temp'=X, max_temp=X}]
  visited = visited or { filter={} }
  if unum == nil or fluidbox == nil or visited[unum] ~= nil then
    return
  end
  visited[unum] = true

  -- special case for generators: they allow steam up to 1000 C, but it is a waste, so limit to the real max
  local max_temp
  if entity.type == 'generator' then
    max_temp = entity.prototype.maximum_temperature
  end
  -- and there is at least one mining drill that declared its output as 'input-output'
  local mining_drill
  if entity.type == 'mining-drill' then
    local fbp = entity.prototype.fluidbox_prototypes
    for _, v in ipairs(fbp) do
      mining_drill = v.production_type
    end
  end

  -- scan, locking onto the first fluid_system_id.
  if debug_fluids or extra_debug then
    clog('fluid visiting [%s] name=%s type=%s #fluidbox=%s', unum, entity.name, entity.type, #fluidbox)
  end
  for idx = 1, #fluidbox do
    local fluid = fluidbox[idx]
    local id = fluidbox.get_fluid_system_id(idx)
    if id ~= nil and (sysid == nil or id == sysid) then
      sysid = id
      local conn = fluidbox.get_connections(idx)
      local filt = fluidbox.get_filter(idx)
      local pipes = fluidbox.get_pipe_connections(idx)

      if debug_fluids or extra_debug then
        clog("   [%s] id=%s capacity=%s fluid=%s filt=%s lock=%s #conn=%s #pipes=%s mining_drill=%s", idx,
          id,
          fluidbox.get_capacity(idx),
          serpent.line(fluid),
          serpent.line(filt),
          serpent.line(fluidbox.get_locked_fluid(idx)),
          #conn,
          #pipes, serpent.line(mining_drill))
      end

      -- fluid holds what is currently present
      if fluid ~= nil then
        local tt = visited.contents[fluid.name]
        if tt == nil then
          tt = {}
          visited.contents[fluid.name] = tt
        end
        tt[fluid.temperature] = (tt[fluid.temperature] or 0) + fluid.amount
      end

      --[[
        ["uranium-ore"] = {
          ...
          minable = {
            fluid_amount = 10,
            mining_particle = "stone-particle",
            mining_time = 2,
            required_fluid = "sulfuric-acid",
            result = "uranium-ore"
          },
          ..
        }

      FIXME: have to scan for resources under the drill and see if they require a fluid to mine.
      For now, just assume if the drill has fluid, then it needs "sulfuric-acid",
      ]]
      if filt == nil and mining_drill == 'input-output' then
        local sap = game.fluid_prototypes["sulfuric-acid"]
        if sap ~= nil then
          filt = { name = "sulfuric-acid", minimum_temperature = sap.default_temperature, maximum_temperature = sap.default_temperature }
        end
      end

      -- only care about a fluidbox with pipe connections
      if #pipes > 0 then
        -- only update the flow_direction if there is a filter
        if filt ~= nil then
          local f = visited.filter
          local old = f[filt.name]
          if old == nil then
            old = { minimum_temperature=filt.minimum_temperature, maximum_temperature=filt.maximum_temperature }
            f[filt.name] = old
          else
            old.minimum_temperature = math.max(old.minimum_temperature, filt.minimum_temperature)
            old.maximum_temperature = math.min(old.maximum_temperature, filt.maximum_temperature)
          end
          old.output_override = (mining_drill == 'output')
          old.mining_drill = mining_drill
          -- correct the max steam temp for generators
          if max_temp ~= nil and max_temp < old.maximum_temperature then
            old.maximum_temperature = max_temp
          end
          for _, pip in ipairs(pipes) do
            visited.flows[pip.flow_direction] = true
          end
        end

        for ci = 1, #conn do
          search_fluid_system(conn[ci].owner, sysid, visited, extra_debug)
        end
      end
    end
  end
end

--[[
Autoconfigure a network tank.

@returns the config or nil if autoconfig is not possible.
Example:
  {
    type = "take",
    fluid = "water",
    buffer = 10000,
    limit = 0,
    no_limit = true,
    minimum_temperature = 15,
    maximum_temperature = 25,
    temperature = 15,
  }

  {
    type = "give",
    limit = 0,
    no_limit = true,
  }
]]
function M.auto_config(entity, extra_debug)
  -- sanity check
  if entity == nil or not entity.valid then
    return -- nil
  end
  local fluidbox = entity.fluidbox
  if fluidbox == nil or #fluidbox ~= 1 then
    return -- nil
  end
  local info = GlobalState.get_tank_info(entity.unit_number)
  if info == nil then
    return -- nil
  end

  if entity.name == 'network-tank-provider' then

  end

  if debug_fluids or extra_debug then
    clog("[%s] auto config %s @ %s", entity.unit_number, entity.name, serpent.line(entity.position))
  end

  local sysid = fluidbox.get_fluid_system_id(1)
  local visited = { filter={}, flows={}, contents={} }

  search_fluid_system(entity, sysid, visited, extra_debug)
  if debug_fluids or extra_debug then
    clog(" ==> filt=%s  flow=%s cont=%s", serpent.line(visited.filter), serpent.line(visited.flows), serpent.line(visited.contents))
  end

  -- if there are no filters, then we can't auto-config
  if next(visited.filter) == nil then
    --clog("network-tank: AUTO: Connect to a fluid provider or consumer")
    return
  end

  -- if there are multitple filters, then we can't auto-config
  if table_size(visited.filter) ~= 1 then
    --clog("network-tank: AUTO: Too many fluids: %s", serpent.line(visited.filter))
    return
  end

  -- if there are multiple flow types, then we can't auto-config
  if table_size(visited.flows) ~= 1 then
    --clog("network-tank: AUTO: Too many connections.")
    return -- table.deepcopy(default_config)
  end

  -- if anything is feeding into the fluid network, then we must be providing
  if visited.flows.output == true then
    return table.deepcopy(default_config)
  end

  -- single input or input-output, find the best fluid temperature
  local name, filt = next(visited.filter)

  -- if we have an input-output, then we need to wait to see if there is fluid provided
  if visited.flows['input-output'] == true then
    if filt.output_override == true then
      return table.deepcopy(default_config)
    end
  end

  local fluid_proto = game.fluid_prototypes[name]
  if fluid_proto == nil then
    return table.deepcopy(default_config)
  end

  -- autoconfig sets a min/max temp instead of an absolute temp
  local config = {
    type = "take",
    fluid = name,
    buffer = constants.DEFAULT_TANK_REQUEST,
    limit = 0,
    no_limit = true,
    minimum_temperature = filt.minimum_temperature,
    maximum_temperature = filt.maximum_temperature,
    --temperature = fluid_proto.default_temperature,
  }

--[[
  -- pick a temperature, stick with the default if none available
  local temps = GlobalState.get_fluids()[name]
  if temps ~= nil then
    local max_temp
    local min_temp
    for temp, _ in pairs(temps) do
      local f_temp = tonumber(temp)/1000
      if f_temp >= filt.minimum_temperature and f_temp <= filt.maximum_temperature then
        if max_temp == nil or f_temp > max_temp then
          max_temp = f_temp
        end
      end
    end
    if max_temp ~= nil then
      config.temperature = max_temp
    end
  end
]]
  return config
end

return M
