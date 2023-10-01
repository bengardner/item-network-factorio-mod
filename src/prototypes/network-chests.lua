--[[
Bulk Chests:
 - network-chest-provider : fitler with bar - will move anything in the chest to network (respecting global limit)
 - network-chest-requester : use logistic-chest-buffer as base, satisfy requests from net (as usual?)
]]
local constants = require "src.constants"
local Paths = require "src.Paths"

local M = {}

local function add_chest(variant)
  local name = "network-chest-" .. variant
  local override_item_name = "iron-chest"
  local override_prototype = "container"

  local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
  entity.name = name
  entity.minable.result = name

  -- update graphics
  entity.picture.layers[1].filename = Paths.graphics .. "/entities/network-chest-" .. variant .. ".png"
  entity.picture.layers[1].hr_version.filename = Paths.graphics .. "/entities/hr-network-chest-" .. variant .. ".png"
  entity.picture.layers[1].hr_version.height = 80
  entity.picture.layers[1].hr_version.width = 64
  entity.icon = Paths.graphics .. "/icons/network-chest-" .. variant .. ".png"

  -- update inventory
  entity.inventory_size = 39 -- constants.NUM_INVENTORY_SLOTS
  entity.inventory_type = "with_filters_and_bar"


  -- create the item
  local item = table.deepcopy(data.raw["item"][override_item_name])
  item.name = name
  item.place_result = name
  item.order = "a[items]-0[network-chest]-" .. variant


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
  --add_chest("requester") -- currently useless
  add_chest("provider")
end

M.main()
