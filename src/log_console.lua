--[[
  I got tired of writing game.print(string.format(...)).

  Prints formatted text to the console for debug.
]]
local M = {}

function M.log(...)
  local text = string.format(...)
  print(text)
  -- NOTE: printing to the console in a conditional manner causes desync
  --if game ~= nil then
  --  game.print(text)
  --end
end

return M
