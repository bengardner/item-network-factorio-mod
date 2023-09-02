--[[
Game plan:
duplicate logistic chests.
 - Provider : golem will grab from this to satisfy a request and grab whatever is available if nearby
 - Storage  : golem will grab from and insert into this chest
   drop off point when it has too much inventory
 - Requester (buffer): golem will read requests and fetch material to satisfy requests

 tem-network will satisfy requests, so this is bunk.
]]
local M = {}

local function add_chest(variant)
  local name = "golem-chest-" .. variant
  local override_item_name = "logistic-chest-" .. variant
  local override_prototype = "logistic-container"

  local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
  entity.name = name
  entity.minable.result = name
  --entity.picture.layers[1].filename = Paths.graphics .. "/entities/network-chest-steel.png"
  --entity.picture.layers[1].hr_version.filename = Paths.graphics .. "/entities/hr-network-chest-steel.png"
  --entity.picture.layers[1].hr_version.height = 80
  --entity.picture.layers[1].hr_version.width = 64
  --entity.icon = Paths.graphics .. "/icons/network-chest-steel.png"
  -- smaller than an iron chest
  entity.inventory_size = 19 -- really small to discourage use after logistics is researched
  --entity.inventory_type = "with_filters_and_bar"

  local item = table.deepcopy(data.raw["item"][override_item_name])
  item.name = name
  item.place_result = name
  --item.order = item.order
  --item.subgroup = "golem-chest"

  local recipe = {
    name = name,
    type = "recipe",
    enabled = true,
    energy_required = 0.5,
    ingredients = {
      { "iron-chest", 1 },
      { "electronic-circuit", 2 }
    }, -- iron chest + 2x circuit board
    result = name,
    result_count = 1,
  }

  data:extend({ entity, item, recipe })
end

function M.main()
  add_chest("buffer")
  add_chest("storage")
  add_chest("passive-provider")
end

M.main()
