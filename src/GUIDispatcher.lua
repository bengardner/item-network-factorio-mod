--[[
Helper that dispatches GUI events based on a supplied tag.
Slightly easier to use than '__stdlib__/stdlib/event/gui'
]]
local Event = require('__stdlib__/stdlib/event/event')
local table = require('__stdlib__/stdlib/utils/table')

local GUIDispatcher = {}

GUIDispatcher.ON_CONFIRM_KEYPRESS = "cin-gui-confirm"
GUIDispatcher.ON_COPY_SETTINGS_KEYPRESS = "cin-copy-entity-settings"
GUIDispatcher.ON_COPY_CONDITIONS_KEYPRESS = "cin-copy-entity-conditions"

-- REVISIT: don't add stuff until register is called?
-- { on_click = { event_tag = fn, ... }, ... }
local registered_tagged_events = {
  [defines.events.on_gui_click] = {},
  [defines.events.on_gui_closed] = {},
  [defines.events.on_gui_value_changed] = {},
  [defines.events.on_gui_text_changed] = {},
  [defines.events.on_gui_elem_changed] = {},
  [defines.events.on_gui_checked_state_changed] = {},
  [defines.events.on_gui_selection_state_changed] = {},

  [GUIDispatcher.ON_CONFIRM_KEYPRESS] = {},
  [GUIDispatcher.ON_COPY_SETTINGS_KEYPRESS] = {},
  [GUIDispatcher.ON_COPY_CONDITIONS_KEYPRESS] = {},

  [defines.events.on_gui_confirmed] = {},
  [defines.events.on_gui_opened] = {},
  [defines.events.on_gui_location_changed] = {},
}
-- { on_click = { fn1, fn2, ... }, ... }
local registered_events = table.deepcopy(registered_tagged_events)

function GUIDispatcher.register(event_name, event_tag, handler)
  if event_tag then
    registered_tagged_events[event_name][event_tag] = handler
  else
    table.insert(registered_events[event_name], handler)
  end
end

function GUIDispatcher.on_event(event)
  local player = game.get_player(event.player_index)
  local tags = (event.element or {}).tags or {}
  local event_name = event.input_name or event.name
  local event_tags = tags['event']
  local fired_handlers = {}

  -- convert a simple tag to a table: { event = "foo" } => { event = { "foo" = true } }
  if type(event_tags) == "string" then
    event_tags = { [event_tags] = true }
  end

  if event_tags then
    for event_tag, _ in pairs(event_tags) do
      local handler = registered_tagged_events[event_name][event_tag]
      if handler then
        handler(event, tags, player)
        fired_handlers[handler] = true
      end
    end
  end

  -- fire all handlers that accept all events
  for event_tag, fn in pairs(registered_events[event_name]) do
    if fired_handlers[fn] == nil then
      fn(event, nil, player)
    end
  end
end

-- Register events handled by GUIDispatcher
Event.on_event(defines.events.on_gui_opened, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_closed, GUIDispatcher.on_event)

Event.on_event(defines.events.on_gui_click, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_value_changed, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_text_changed, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_elem_changed, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_checked_state_changed, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_confirmed, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_selection_state_changed, GUIDispatcher.on_event)
Event.on_event(defines.events.on_gui_location_changed, GUIDispatcher.on_event)

-- custom events
--Event.on_event(GUIDispatcher.ON_CONFIRM_KEYPRESS, GUIDispatcher.on_event)
--Event.on_event(GUIDispatcher.ON_COPY_SETTINGS_KEYPRESS, GUIDispatcher.on_event)
--Event.on_event(GUIDispatcher.ON_COPY_CONDITIONS_KEYPRESS, GUIDispatcher.on_event)

return GUIDispatcher
