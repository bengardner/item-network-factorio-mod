--[[
  Wraps on_event() so that multiple functions can be attached.
  No order promises.

  Attach an event or list of events using EventDispatch.add().
  And that is all you do.

  The handler is of the form: handler(EventData)

  EventData contains at least the following fields:
   - name
   - tick
   - mod_name
  The remaining fields depend on 'name'.

  If using for a "custom-event", the event_id will be a string.
  For anything else, the string name will be
]]
local log = require("src.log_console").log

local M = {}

-- event_map[event_id] = { handler1, handler2, handler3 }
M.event_map = {}

-- wrapper function that is filtered on element.tags.event
-- event_tag_map[event_id][tags.event] = handler
M.event_tag_map = {}

M.custom_name_id = {} -- maps the name to the id
M.custom_id_name = {}

-- dispatches simple events
local function dispatch(event_id, event_data)
  -- dispatch to all simple handlers
  local mm = M.event_map[event_id]
  if mm ~= nil then
    for _, handler in pairs(mm) do
      handler(event_data)
    end
  end

  local etm = M.event_tag_map[event_id]
  if etm ~= nil then
    local function do_tag(tag)
      if tag ~= nil then
        local handler = M.event_tag_map[event_id][tag]
        if type(handler) == "function" then
          handler(event_data)
        end
      end
    end

    -- dispatch to tagged elements
    local element = event_data.element
    if element ~= nil and element.valid then
      do_tag(element.name)
      if element.valid then
        do_tag(element.tags.event)
      end
    end
  end
end

-- Convert a string to a numeric event ID
function M.resolve_event(event)
  if type(event) == "string" then
    -- Resolve "on_gui_click", etc, to their numeric
    local tmp = defines.events[event]
    if tmp ~= nil then
      event = tmp
    end
  end
  return event
end

--[[
Register a handler for an event.
If name is set, then it will only be called if event_data.element.tags.event matches.

@event can be a string or number
@handler is the function
@name is an optional filter on event_data.element.tags.event
]]
local function add_one(event, handler, name)
  assert(event ~= nil and handler ~= nil, "invalid call")
  local event_id = M.resolve_event(event)

  local mm = M.event_map[event_id]
  if mm == nil then
    mm = {}
    M.event_map[event_id] = mm

    -- convert the old handler, if possible
    local old_handler = script.get_event_handler(event_id)
    assert(old_handler == nil, string.format("%s already set", event))
    if old_handler ~= nil then
      assert(script.get_event_filter(event_id) == nil, "filters cannot be used with EventDispatch")
      table.insert(mm, function (ev_id, ev_data)
        old_handler(ev_data)
      end)
    end

    -- set the new handler for the event
    script.on_event(event_id, function (event_data)
      dispatch(event_id, event_data)
    end)
  end

  if name ~= nil then
    -- add the tag event filter
    local tt = M.event_tag_map[event_id]
    if tt == nil then
      tt = {}
      M.event_tag_map[event_id] = tt
    end
    tt[name] = handler
  else
    -- no element filter
    table.insert(mm, handler)
  end
end

function M.add(event, handler, name)
  -- split a list into individual add calls
  if type(event) == "table" and handler == nil then
    for _, v in pairs(event) do
      if v.event ~= nil and v.handler ~= nil then
        add_one(v.event, v.handler, v.name)
      end
    end
    return
  else
    add_one(event, handler, name)
  end
end

-- replacement for script.on_event() with NO filters
function M.on_event(event, handler, filter)
  assert(filter == nil, "Filters not supported")
  M.add(event, handler)
end

return M
