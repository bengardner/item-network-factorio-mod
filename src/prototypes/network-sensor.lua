
local name = "network-sensor"
local override_item_name = "constant-combinator"
local override_prototype = "constant-combinator"

local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
entity.name = name
entity.minable.result = name
-- Need enough to hold every item we might build
-- We could scan in data-final-fixes to get a more accurate count, but that is ~1700 items.
entity.item_slot_count = 1000

local item = table.deepcopy(data.raw["item"][override_item_name])
item.name = name
item.place_result = name
item.order = item.order .. "2"

local recipe = table.deepcopy(data.raw["recipe"][override_item_name])
recipe.name = name
recipe.result = name

data:extend({ entity, item, recipe })
