local Paths = require "src.Paths"

local logo = {
  type = "sprite",
  name = "cin-logo",
  filename = Paths.graphics .. "/icons/logo.png",
  priority = "medium",
  width = 64,
  height = 64,
  generate_sdf = true
}

local logo_disabled = {
  type = "sprite",
  name = "cin-logo-disabled",
  filename = Paths.graphics .. "/icons/logo-disabled.png",
  priority = "medium",
  width = 64,
  height = 64,
  generate_sdf = true
}

local asterisk_icon = {
  type = "sprite",
  name = "cin-asterisk-icon",
  filename = Paths.graphics .. "/icons/icon-asterisk.png",
  priority = "medium",
  width = 28,
  height = 28,
  generate_sdf = true
}

local changing_icon = {
  type = "sprite",
  name = "cin-changing-icon",
  filename = Paths.graphics .. "/icons/icon-changing.png",
  priority = "medium",
  width = 72,
  height = 72,
  generate_sdf = true,
  scale = 0.5,
  mipmap_count = 3,
  flags = { "icon" },
}

data:extend({
  logo,
  logo_disabled,
  asterisk_icon,
  changing_icon
})
