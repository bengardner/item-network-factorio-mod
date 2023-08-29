local GlobalState = require "src.GlobalState"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')

local M = {}

--[[
Relevant fields:

entity.get_control_behavior()

LuaConstantCombinatorControlBehavior
  set_signal(index, signal?)
    Sets the signal at the given index.
  get_signal(index) 	 → Signal
    Gets the signal at the given index.
  help() 	 → string
    All methods and properties that this object supports.
  parameters [RW] 	:: array[ConstantCombinatorParameters]?
      This constant combinator's parameters.
  enabled [RW] 	:: boolean
      Turns this constant combinator on and off.
  signals_count [R] 	:: uint
    The number of signals this constant combinator supports.
  valid [R] 	:: boolean
    Is this object valid?
  object_name [R] 	:: string
    The class name of this object.

ConstantCombinatorParameters :: table
  signal 	:: SignalID     Signal to emit.
  count 	:: int          Value of the signal to emit.
  index 	:: uint         Index of the constant combinator's slot to set this signal to.

SignalID :: table
  type 	:: string
    "item", "fluid", or "virtual".
  name 	:: string?
    Name of the item, fluid or virtual signal.

Game plan:
  - build up a set of signals, set parameters
]]

-- want a consistent sort order (sort by signal.type and then signal.name)
local function compare_params(left, right)
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
  -- have to set the index after sorting
  table.sort(params, compare_params)
  for index, param in ipairs(params) do
    param.index = index
  end
  return params
end

function M.service_sensors()
  local params
  -- all sensors get the same parameters
  for _, entity in pairs(GlobalState.sensor_get_list()) do
    if entity.valid then
      local cb = entity.get_control_behavior()
      if cb ~= nil then
        if params == nil then
          params = M.get_parameters()
        end
        cb.parameters = params
      end
    end
  end
end

function M.register_entity(event)
  local entity = event.created_entity
  if entity == nil then
    entity = event.entity
  end
  if entity ~= nil and entity.name == "network-sensor" then
    GlobalState.sensor_add(entity)
  end
end

function M.deregister_entity(event)
  local entity = event.entity
  if entity ~= nil and entity.name == "network-sensor" then
    GlobalState.sensor_del(entity)
  end
end

Event.on_event(
  {
    defines.events.on_built_entity,
    defines.events.script_raised_built,
    defines.events.on_entity_cloned,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_revive,
  },
  M.register_entity
)

-- delete
Event.on_event(
  {
    defines.events.on_pre_player_mined_item,
    defines.events.on_robot_mined_entity,
    defines.events.script_raised_destroy,
    defines.events.on_entity_died,
    defines.events.on_marked_for_deconstruction,
  },
  M.deregister_entity
)

Event.on_nth_tick(120, M.service_sensors)

return M
