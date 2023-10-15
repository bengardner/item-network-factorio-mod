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
local Gui = require('__stdlib__/stdlib/event/gui')
local item_utils = require "src.item_utils"

-- M is the module that supplies 'create()'
local M = {}

local NetInv = {}

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiNetworkFluid
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiNetworkFluid = value
end

function M.create(parent, player)
  local self = {
    player = player,
    elems = {},
    use_group = false,
  }

  -- set index so we can call self:refresh() or M.refresh(self)
  setmetatable(self, { __index = NetInv })

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

  self.elems.checkbox = hdr.add({
    name = UiConstants.NETFLUID_GROUP,
    type = "checkbox",
    caption = "Group",
    style = "checkbox",
    state = true,
  })

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

function NetInv.destroy(self)
  if self.frame ~= nil then
    self.frame.destroy() -- destroy the GUI
    self.frame = nil
  end
  gui_set(self.player.index, nil)
end

local function get_list_of_fluids()
  local items = {}

  local fluids_to_display = GlobalState.get_fluids()
  for fluid_name, fluid_temps in pairs(fluids_to_display) do
    if game.fluid_prototypes[fluid_name] ~= nil then
      for temp, count in pairs(fluid_temps) do
        table.insert(items, { item = fluid_name, count = count, temp = temp })
      end
    end
  end
  -- sort by order, then temperature
  table.sort(items, item_utils.entry_compare_fluids)
  return items
end

-- REVISIT: this should be in the utils file
local function get_sprite_button_def(item)
  local tooltip
  local sprite_path

  if item.temp ~= nil and game.fluid_prototypes[item.item] ~= nil then
    tooltip = item_utils.get_fluid_inventory_tooltip(item.item, item.temp, item.count)
    sprite_path = "fluid/" .. item.item
    return {
      type = "sprite-button",
      sprite = sprite_path,
      tooltip = tooltip,
    }
  end
end

function NetInv:refresh()
  local item_table = self.elems.item_table
  item_table.clear()

  local total_items = 0
  local total_count = 0
  local use_group = self.use_group

  local last_fluid_name

  -- add the fluids
  local items = get_list_of_fluids()
  for _, item in ipairs(items) do
    if use_group and last_fluid_name ~= nil and item.item ~= last_fluid_name then
      item_utils.pad_item_table_row(item_table)
    end
    local sprite_button = get_sprite_button_def(item)
    if sprite_button then
      local sprite_button_inst = item_table.add(sprite_button)
      sprite_button_inst.number = item.count
      total_items = total_items + 1
      total_count = total_count + item.count
    end
    last_fluid_name = item.item
  end

  self.elems.title.caption = string.format("Network Fluids - %.0f types, %.0f total", total_items, total_count)
end

local function on_group_check_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    self.use_group = not self.use_group
    self:refresh()
  end
end

Gui.on_checked_state_changed(UiConstants.NETFLUID_GROUP, on_group_check_changed)

return M
