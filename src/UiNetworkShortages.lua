--[[
  Creates the Network invetory GuiElement tree under the specified parent GuiElement.
  There can be only one per character,

  Inteface for the module:
  - M.create(parent, player)
    Create the GUI element tree as a child of @parent for @player

  Exposed interface for the "instance"
  - inst.frame
    This is the top-most GUI element. Useful to assign to a tabbed pane.
  - inst:destroy()
    This destroys any data associated with the instance and the GUI.
  - inst:refresh()
    This refreshes the data in the display.
]]
local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local item_utils = require "src.item_utils"

-- M is the module that supplies 'create()'
local M = {}

local NetLimits = {}

local NetShortage__metatable = { __index = NetLimits }
script.register_metatable("NetShortage", NetShortage__metatable)

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiNetworkShortages
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiNetworkShortages = value
end

function M.create(parent, player)
  local self = {
    player = player,
    elems = {},
  }

  -- set index so we can call self:refresh() or M.refresh(self)
  setmetatable(self, NetShortage__metatable)

  local vert_flow = parent.add({
    type = "flow",
    direction = "vertical",
  })
  self.frame = vert_flow

  local inv_frame = vert_flow.add({
    type = "frame",
    style = "character_inventory_frame",
    --style = "inventory_frame",
  })
  local scroll_pane = inv_frame.add({
    type = "scroll-pane",
    style = "character_inventory_scroll_pane",
    --style = "entity_inventory_scroll_pane",
  }) -- 424, 728 or 400,712
  scroll_pane.style.width = 424

  local hdr = scroll_pane.add({
    type = "flow",
    direction = "horizontal",
  })
  hdr.style.size = { 400, 28 }

  self.elems.title = hdr.add({
    type = "label",
    caption = "Network Items",
    style = "inventory_label",
  })
  local hdr_spacer = hdr.add({ type = "empty-widget" })
  hdr_spacer.style.horizontally_stretchable = true

  local item_table = scroll_pane.add({
    type = "table",
    name = "item_table",
    style = "slot_table",
    column_count = 10
  })
  self.elems.item_table = item_table

  gui_set(player.index, self)

  -- populate the table
  self:refresh()

  return self
end

function NetLimits:destroy()
  if self.frame ~= nil then
    self.frame.destroy() -- destroy the GUI
    self.frame = nil
  end
  gui_set(self.player.index, nil)
end

local function get_entry_list()
  local items = {}

  -- add item shortages
  local missing = GlobalState.missing_item_filter()
  for item_name, count in pairs(missing) do
    -- sometime shortages can have invalid item names.
    if game.item_prototypes[item_name] ~= nil then
      table.insert(items, { item = item_name, count = count })
    end
  end

  -- add fluid shortages
  missing = GlobalState.missing_fluid_filter()
  for fluid_key, count in pairs(missing) do
    local fluid_name, temp, temp2 = GlobalState.fluid_temp_key_decode(fluid_key)
    if game.fluid_prototypes[fluid_name] ~= nil then
      table.insert(items, { item = fluid_name, count = count, temp = temp, temp2 = temp2 })
    end
  end
  -- sort so that the largest shortages are first
  table.sort(items, item_utils.entry_compare_count)
  return items
end

-- REVISIT: this should be in the utils file
local function get_sprite_button_def(item)
  local tooltip
  local sprite_path
  local tags
  if item.temp == nil then
    tooltip = item_utils.get_item_shortage_tooltip(item.item, item.count)
    tags = { event = UiConstants.NETITEM_ITEM, item = item.item }
    sprite_path = "item/" .. item.item
  else
    tooltip = item_utils.get_fluid_shortage_tooltip(item.item, item.count, item.temp, item.temp2)
    sprite_path = "fluid/" .. item.item
  end
  return {
    type = "sprite-button",
    sprite = sprite_path,
    tooltip = tooltip,
    tags = tags,
  }
end

function NetLimits:refresh()
  local item_table = self.elems.item_table
  item_table.clear()

  local total_items = 0
  local total_count = 0

  -- add the fluids
  for _, item in ipairs(get_entry_list()) do
    local sprite_button = get_sprite_button_def(item)
    local sprite_button_inst = item_table.add(sprite_button)
    sprite_button_inst.number = item.count
    total_items = total_items + 1
    total_count = total_count + item.count
  end

  self.elems.title.caption = string.format("Network Shortages - %.0f types, %.0f total", total_items, total_count)
end

return M
