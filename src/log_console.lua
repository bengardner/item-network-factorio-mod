--[[
  I got tired of writing game.print(string.format(...)).

  Prints formatted text to the console for debug.
]]
local M = {}

function M.log(...)
  if game ~= nil then
    game.print(string.format(...))
  end
end

return M
