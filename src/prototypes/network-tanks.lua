local constants = require "src.constants"
local Paths = require "src.Paths"

local function add_network_tank(name, is_output)
  local base_level = -0.5
  local fb_type = "input"
  if is_output then
    -- requests from the network and dumps into other entities
    fb_type = "output"
    base_level = 0.5
  end

  local override_item_name = "storage-tank"

  local fname = Paths.graphics .. "/entities/" .. name .. ".png"

  local entity = {
    name = name,
    type = "storage-tank",
    flags = {
      "placeable-neutral",
      "player-creation",
      "fast-replaceable-no-build-while-moving",
    },
    icon = fname,
    icon_size = 64,
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    collision_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
    window_bounding_box = { { -1, -0.5 }, { 1, 0.5 } },
    drawing_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    fluid_box = {
      base_area = constants.TANK_AREA,
      height = constants.TANK_HEIGHT,
      pipe_covers = pipecoverspictures(),
      pipe_connections =
      {
        { position = { 0, 1 }, type = fb_type },
      },
    },
    two_direction_only = false,
    pictures = {
      picture = {
        sheet = {
          filename = fname,
          size = 128,
          scale = 0.5,
        },
      },
      window_background = {
        filename = Paths.graphics .. "/empty-pixel.png",
        size = 1,
      },
      fluid_background = {
        filename = Paths.graphics .. "/empty-pixel.png",
        size = {1, 1},
      },
      flow_sprite = {
        filename = Paths.graphics .. "/empty-pixel.png",
        size = 1,
      },
      gas_flow = {
        filename = Paths.graphics .. "/empty-pixel.png",
        size = 1,
      },
    },
    flow_length_in_ticks = 1,
    minable = {
      mining_time = 0.5,
      result = name,
    },
    se_allow_in_space = true,
    allow_copy_paste = true,
    additional_pastable_entities = { name },
    max_health = 200,
  }

  local item = table.deepcopy(data.raw["item"][override_item_name])
  item.name = name
  item.place_result = name
  item.icon = Paths.graphics .. "/items/" .. name .. ".png"
  item.size = 64

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

for k, v in pairs(constants.NETWORK_TANK_NAMES) do
  if v == true or v == false then
    add_network_tank(k, v)
  end
end
