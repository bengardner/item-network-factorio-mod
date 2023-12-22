--[[
Bulk Chests:
 - network-chest-provider : fitler with bar - will move anything in the chest to network (respecting global limit)
 - network-chest-requester : use logistic-chest-buffer as base, satisfy requests from net (as usual?)
]]
local constants = require "src.constants"
local Paths = require "src.Paths"

local M = {}

local function add_chest(name)
  local override_item_name = "iron-chest"
  local override_prototype = "container"

  local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
  entity.name = name
  entity.minable.result = name

  entity.next_upgrade = nil
  entity.flags = {
    "not-upgradable",
    "placeable-neutral",
    "player-creation"
  }

  -- update graphics
  --entity.picture.layers[1].filename = Paths.graphics .. "/entities/" .. name .. ".png"
  entity.picture.layers = {
    {
      filename = Paths.graphics .. "/entities/hr-" .. name .. ".png",
      height = 80,
      width = 64,
      hr_version = {
        filename = Paths.graphics .. "/entities/hr-" .. name .. ".png",
        height = 80,
        width = 64,
        priority = "extra-high",
        scale = 0.5,
        shift = { -0.015625, -0.015625 },
      },
    },
    {
      draw_as_shadow = true,
      filename = "__base__/graphics/entity/iron-chest/iron-chest-shadow.png",
      height = 26,
      hr_version = {
        draw_as_shadow = true,
        filename = "__base__/graphics/entity/iron-chest/hr-iron-chest-shadow.png",
        height = 50,
        priority = "extra-high",
        scale = 0.5,
        shift = {
          0.328125,
          0.1875
        },
        width = 110
      },
      priority = "extra-high",
      shift = {
        0.3125,
        0.203125
      },
      width = 56
    },
  }
  entity.resistances = {
    { percent = 95, type = "fire" },
    { percent = 95, type = "impact" },
    { percent = 95, type = "acid" },
  }

  entity.icon = Paths.graphics .. "/icons/" .. name .. ".png"

  -- update inventory
  entity.inventory_size = 40 -- constants.NUM_INVENTORY_SLOTS
  -- no filters
  -- entity.inventory_type = "with_filters_and_bar"
  entity.inventory_type = "with_bar"
  entity.enable_inventory_bar = false

  -- create the item
  local item = table.deepcopy(data.raw["item"][override_item_name])
  item.name = name
  item.place_result = name
  item.order = "a[items]-0[" .. name .. "]"
  item.icon = Paths.graphics .. "/icons/" .. name .. ".png"


  -- create a dummy inventory
  local recipe = {
    name = name,
    type = "recipe",
    enabled = true,
    energy_required = 0.5,
    ingredients = {
      --{ "iron-chest", 1 },
      --{ "electronic-circuit", 2 }
    },
    result = name,
    result_count = 1,
  }

  data:extend({ entity, item, recipe })
end

function M.main()
  -- FIXME: these should be the logistic chests with inv size of 19
  add_chest("network-chest")
  add_chest("network-chest-provider")
  --add_chest("network-chest-requester") -- currently useless
end

M.main()
