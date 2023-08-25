--[[
  Wraps on_event() so that multiple functions can be attached.
  No order promises.
]]
local M = {}

M.event_map = {}

function M.dispatch(event_id, event)
  local mm = M.event_map[event_id]
  if mm ~= nil then
    for _, func in pairs(mm) do
      func(event)
    end
  end
end

-- register a handler for an event
function M.add(event_id, func, name)
  local mm = M.event_map[event_id]
  if mm == nil then
    mm = {}
    M.event_map[event_id] = mm

    local old_handler = script.get_event_handler(event_id)

    script.on_event(event_id, function (event)
      M.dispatch(event_id, event)
    end)
    if old_handler ~= nil then
      table.insert(mm, old_handler)
    end
  end

  if name ~= nil then
    mm[name] = func
  else
    table.insert(mm, func)
  end
end

function M.del(event_id, name)
  local mm = M.event_map[event_id]
  if mm ~= nil then
    mm[name]= nil
  end
end
return M
