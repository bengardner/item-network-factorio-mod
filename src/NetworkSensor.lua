--[[
  Implenets a Constant Combinator that exposes the Item Network content.

  TODO: add a variant that exposes the Limits instead of the content.
]]
local GlobalState = require "src.GlobalState"
local Event = require('__stdlib__/stdlib/event/event')

local M = {}

-- want a consistent sort order (sort by signal.type and then signal.name)
local function compare_control_params(left, right)
  if left.signal.type ~= right.signal.type then
    return left.signal.type < right.signal.type
  end
  return left.signal.name < right.signal.name
end

function M.get_parameters()
  local params = {}
  for item, count in pairs(GlobalState.get_items()) do
    table.insert(params, {
      signal = { type = "item", name = item },
      count = count,
    })
  end
  for fluid_name, fluid_temps in pairs(GlobalState.get_fluids()) do
    if game.fluid_prototypes[fluid_name] ~= nil then
      local max_temp
      local max_count
      for temp, count in pairs(fluid_temps) do
        local f_temp = tonumber(temp)
        if max_temp == nil or max_temp < f_temp then
          max_temp = f_temp
          max_count = count
        end
      end
      if max_count ~= nil then
        table.insert(params, {
          signal = { type = "fluid", name = fluid_name },
          count = max_count,
        })
      end
    end
  end
  -- have to set the index after sorting
  table.sort(params, compare_control_params)
  for index, param in ipairs(params) do
    param.index = index
  end
  return params
end

function M.get_limit_parameters()
  local params = {}
  for item, count in pairs(GlobalState.get_limits()) do
    local name, temp = GlobalState.fluid_temp_key_decode(item)
    if temp == nil then
      table.insert(params, {
        signal = { type = "item", name = name },
        count = math.min(count, 2000000000),
      })
    else
      table.insert(params, {
        signal = { type = "fluid", name = name },
        count = math.min(count, 2000000000),
      })
    end
  end
  -- have to set the index after sorting
  table.sort(params, compare_control_params)
  for index, param in ipairs(params) do
    param.index = index
  end
  return params
end

function M.service_sensors()
  local params
  local params_limit
  local to_del = {}
  -- all sensors get the same parameters, so handle them all in one tick
  for unit_number, entity in pairs(GlobalState.sensor_get_list()) do
    if entity.valid then
      local cb = entity.get_control_behavior()
      if cb ~= nil then
        if entity.name == "network-sensor" then
          if params == nil then
            params = M.get_parameters()
          end
          cb.parameters = params
        else
          if params_limit == nil then
            params_limit = M.get_limit_parameters()
          end
          cb.parameters = params_limit
        end
      end
    else
      table.insert(to_del, unit_number)
    end
  end
  for _, un in ipairs(to_del) do
    GlobalState.sensor_del(un)
  end
end

function M.register_entity(event)
  local entity = event.created_entity or event.entity or event.destination
  if entity ~= nil and (entity.name == "network-sensor" or entity.name == "network-limit-sensor") then
    GlobalState.sensor_add(entity)
  end
end

Event.on_event(
  {
    defines.events.on_built_entity,
    defines.events.on_entity_cloned,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
  },
  M.register_entity
)

--[[
NOTE: We skip the destroy events because we can discard any invalid entities on update.
]]

-- update every 3 seconds
Event.on_nth_tick(3 * 60, M.service_sensors)

return M
