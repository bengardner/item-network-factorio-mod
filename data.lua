local constants = require "src.constants"
local Paths = require "src.Paths"
local Hotkeys = require "src.Hotkeys"

require "src.prototypes.network-chests"
require "src.prototypes.network-loader"
require "src.prototypes.network-sensor"
require "src.prototypes.network-tanks"

local M = {}

function M.main()

  -- TODO: does this deserve a separate file?
  data:extend(Hotkeys.hotkeys)

  -- TODO: move this all to a 'gui' prototypes file?
  data:extend({
    { type = "sprite", name = "inet_slot_empty_inset", filename = Paths.graphics .. "/icons/slot-inset-empty.png", width=40, height=40, flags = { "gui-icon" } },
    { type = "sprite", name = "inet_slot_empty_outset", filename = Paths.graphics .. "/icons/slot-outset-empty.png", width=40, height=40, flags = { "gui-icon" } },
  })

  local fab = Paths.graphics .. "/frame-action-icons.png"

  data:extend({
    { type = "sprite", name = "flib_pin_black", filename = fab, position = { 0, 0 }, size = 32, flags = { "gui-icon" } },
    { type = "sprite", name = "flib_pin_white", filename = fab, position = { 32, 0 }, size = 32, flags = { "gui-icon" } },
    {
      type = "sprite",
      name = "flib_pin_disabled",
      filename = fab,
      position = { 64, 0 },
      size = 32,
      flags = { "gui-icon" },
    },
    {
      type = "sprite",
      name = "flib_settings_black",
      filename = fab,
      position = { 0, 32 },
      size = 32,
      flags = { "gui-icon" },
    },
    {
      type = "sprite",
      name = "flib_settings_white",
      filename = fab,
      position = { 32, 32 },
      size = 32,
      flags = { "gui-icon" },
    },
    {
      type = "sprite",
      name = "flib_settings_disabled",
      filename = fab,
      position = { 64, 32 },
      size = 32,
      flags = { "gui-icon" },
    },
  })
end

M.main()
