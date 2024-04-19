--[[
Defines the "network-loader" entity.
]]
local Paths = require "src.Paths"

local M = {}

function M.add_loader()
  local name = "network-loader"

  local entity = {
    name = "network-loader",
    type = "loader-1x1",
    icon = Paths.graphics .. "/entities/express-loader.png",
    icon_size = 64,
    flags = { "placeable-neutral", "player-creation",
      "fast-replaceable-no-build-while-moving" },
    minable = {
      mining_time = 0.2,
      result = "network-loader",
    },
    max_health = 300,
    corpse = "small-remnants",
    collision_box = { { -0.4, -0.45 }, { 0.4, 0.45 } },
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    drawing_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
    animation_speed_coefficient = 32,
    belt_animation_set = data.raw["transport-belt"]["express-transport-belt"]
      .belt_animation_set,
    container_distance = 0.75,
    belt_length = 0.5,
    fast_replaceable_group = "loader",
    filter_count = 1,
    -- https://wiki.factorio.com/Prototype/TransportBeltConnectable#speed
    -- 360 items / sec
    speed = 0.75,
    structure = {
      direction_in = {
        sheet = {
          filename = Paths.graphics .. "/entities/express-loader.png",
          priority = "extra-high",
          shift = { 0.15625, 0.0703125 },
          width = 106 * 2,
          height = 85 * 2,
          y = 85 * 2,
          scale = 0.25,
        },
      },
      direction_out = {
        sheet = {
          filename = Paths.graphics .. "/entities/express-loader.png",
          priority = "extra-high",
          shift = { 0.15625, 0.0703125 },
          width = 106 * 2,
          height = 85 * 2,
          scale = 0.25,
        },
      },
    },
    se_allow_in_space = true,
  }

  local item = {
    name = name,
    type = "item",
    place_result = name,
    icon = Paths.graphics .. "/items/express-loader.png",
    icon_size = 64,
    stack_size = 50,
    subgroup = data.raw["item"]["iron-chest"].subgroup,
    order = data.raw["item"]["iron-chest"].order,
  }

  local recipe = {
    name = name,
    type = "recipe",
    enabled = true,
    energy_required = 0.5,
    ingredients = {},
    result = name,
    result_count = 1,
  }

  data:extend({ entity, item, recipe })
end

M.add_loader()
