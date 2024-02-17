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
local clog = require("src.log_console").log

-- M is the module that supplies 'create()'
local M = {}

local NetLim = {}

local NetLimit__metatable = { __index = NetLim }
script.register_metatable("NetLimit", NetLimit__metatable)

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiNetworkLimits
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiNetworkLimits = value
end

function M.create(parent, player, show_title)
  local self = {
    player = player,
    elems = {},
    use_group = false,
  }

  -- set index so we can call self:refresh() or M.refresh(self)
  setmetatable(self, NetLimit__metatable)

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
    caption = "Network Limits",
    style = "inventory_label",
  })
  local hdr_spacer = hdr.add({ type = "empty-widget" })
  hdr_spacer.style.horizontally_stretchable = true

  self.elems.checkbox = hdr.add({
    name = UiConstants.NETLIMIT_GROUP,
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

  ---------------------------------------------------------------
  -- Edit bar

  local edit_flow = vert_flow.add({
    type = "flow",
    direction = "horizontal",
    name = "edit_flow",
  })
  edit_flow.style.height = 48
  edit_flow.style.vertical_align = "center"
  edit_flow.style.left_padding = 4
  edit_flow.style.right_padding = 4
  self.elems.edit_flow = edit_flow

  -- this chooses whether we show 'item_edit_flow' or 'fluid_edit_flow'
  local dropdown = edit_flow.add({
    name = UiConstants.NETLIMIT_TYPE,
    type = "drop-down",
    caption = "item or Fluid",
    selected_index = 1,
    items = { "item", "fluid" },
  })
  --dropdown.style.horizontally_squashable = true
  dropdown.style.width = 75
  self.elems.edit_type = dropdown

  -- this gets tricky: we create the "item" and "fluid" edit stuff and hide fluid
  local item_edit_flow = edit_flow.add({
    type = "flow",
    direction = "horizontal",
    name = "item_edit",
  })
  self.elems.item_edit = item_edit_flow

  local fluid_edit_flow = edit_flow.add({
    type = "flow",
    direction = "horizontal",
    name = "fluid_edit",
  })
  fluid_edit_flow.visible = false
  fluid_edit_flow.style.vertical_align = "center"
  self.elems.fluid_edit = fluid_edit_flow

  -- add the item selector
  self.elems.item_elem = item_edit_flow.add({
    name = UiConstants.NETLIMIT_SELECT_ITEM,
    type = "choose-elem-button",
    elem_type = "item",
    tooltop = { "", "Click to select an item or click an existing item above" },
  })

  -- add the fluid selector and temperature
  self.elems.fluid_elem = fluid_edit_flow.add({
    name = UiConstants.NETLIMIT_SELECT_FLUID,
    type = "choose-elem-button",
    elem_type = "fluid",
    tooltop = { "", "Click to select an item or click an existing item above" },
  })
  fluid_edit_flow.add({
    type = "label",
    caption = "Temp",
  })
  local tf_temp = fluid_edit_flow.add({
    type = "textfield",
    text = "0",
    numeric = true,
    name = "temperature",
  })
  tf_temp.style.width = 75
  self.elems.temperature = tf_temp

  -- the current/new limit (shared)
  edit_flow.add({
    type = "label",
    caption = "Limit",
  })
  local tf_limit = edit_flow.add({
    type = "textfield",
    text = "0",
    numeric = true,
    name = "new_limit",
  })
  tf_limit.style.width = 100
  self.elems.new_limit = tf_limit

  local pad = edit_flow.add({ type= "empty-widget" })
  pad.style.horizontally_stretchable = true

  -- add save button
  edit_flow.add({
    name = UiConstants.NETLIMIT_SAVE,
    type = "sprite-button",
    sprite = "utility/enter",
    tooltip = { "", "Update limit" },
    style = "frame_action_button",
  })

  gui_set(player.index, self)

  -- populate the table
  self:refresh()

  return self
end

function NetLim.destroy(self)
  if self.frame ~= nil then
    self.frame.destroy() -- destroy the GUI
    self.frame = nil
  end
  gui_set(self.player.index, nil)
end

local function get_limit_items()
  local limits = GlobalState.get_limits()

  -- add a limit for any item/fluid that we have that doesn't have a limit
  for name, _ in pairs(GlobalState.get_items()) do
    if limits[name] == nil then
      limits[name] = GlobalState.get_default_limit(name)
    end
  end
  for name, temp_info in pairs(GlobalState.get_fluids()) do
    for temp, _ in pairs(temp_info) do
      local key = GlobalState.fluid_temp_key_encode(name, temp)
      if limits[key] == nil then
        limits[key] = GlobalState.get_default_limit(key)
      end
    end
  end
  return limits
end

local function get_list_of_items(break_fluid)
  local items = {}
  local fluids = {}

  for item_name, count in pairs(get_limit_items()) do
    local nn, tt = GlobalState.fluid_temp_key_decode(item_name)
    if tt ~= nil then
      if game.fluid_prototypes[nn] ~= nil then
        table.insert(fluids, { item = nn, temp = tt, count = count })
      end
    else
      if game.item_prototypes[nn] ~= nil then
        table.insert(items, { item = item_name, count = count })
      end
    end
  end
  table.sort(fluids, item_utils.entry_compare_fluids)
  table.sort(items, item_utils.entry_compare_items)
  --table.insert(fluids, "break")
  --local last_item
  for _, ent in ipairs(items) do
    --if item_utils.item_need_group_break(last_item, ent.item) then
    --  table.insert(fluids, "break")
    --end
    table.insert(fluids, ent)
    --last_item = ent.item
  end

  return item_utils.entry_list_split_by_group(fluids, break_fluid)
end

-- REVISIT: this should be in the utils file
local function get_sprite_button_def(item)
  local tooltip
  local sprite_path
  local tags
  local name
  if item.temp == nil then
    name = string.format("%s:%s", UiConstants.NETLIMIT_ITEM_BTN, item.item)
    tooltip = item_utils.get_item_limit_tooltip(item.item, item.count)
    tags = { item = item.item }
    sprite_path = "item/" .. item.item
  else
    name = string.format("%s:%s@%s", UiConstants.NETLIMIT_ITEM_BTN, item.item, item.temp)
    tooltip = item_utils.get_fluid_limit_tooltip(item.item, item.temp, item.count)
    tags = { item = item.item, temp = item.temp }
    sprite_path = "fluid/" .. item.item
  end
  return {
    name = name,
    type = "sprite-button",
    sprite = sprite_path,
    tooltip = tooltip,
    tags = tags,
  }
end

function NetLim:refresh()
  local item_table = self.elems.item_table
  item_table.clear()

  local total_items = 0
  local total_count = 0
  local use_group = self.use_group

  -- add the items
  local items = get_list_of_items(self.use_group)
  for _, item in ipairs(items) do
    if type(item) ~= "table" then
      if use_group then
        item_utils.pad_item_table_row(item_table)
      end
    else
      local sprite_button = get_sprite_button_def(item)
      local sprite_button_inst = item_table.add(sprite_button)
      sprite_button_inst.number = item.count
      total_items = total_items + 1
      total_count = total_count + item.count
    end
  end

  self.elems.title.caption = string.format("Network Limits - %s items, %s total", total_items, total_count)
end

-- type_idx: 1=item 2=fluid
local function limit_set_edit_type(self, type_idx)
  self.elems.fluid_edit.visible = (type_idx == 2)
  self.elems.item_edit.visible = (type_idx ~= 2)
  self.elems.edit_type.selected_index = type_idx
end

local function set_new_limit(self, new_limit)
  self.elems.new_limit.text = string.format("%s", new_limit)
  self.elems.new_limit.select(1, 0)
end

local function limit_set_edit_item(self, item_name, item_temp)
  if item_name ~= nil then
    local prot = game.item_prototypes[item_name]
    if prot ~= nil then
      local item_limit = GlobalState.get_limit(item_name)
      --clog("limit_set_edit_item: item [%s] group [%s] subgroup [%s] limit=%s",
      --  item_name, prot.group.name, prot.subgroup.name, item_limit)
      limit_set_edit_type(self, 1)
      self.elems.item_elem.elem_value = item_name
      set_new_limit(self, item_limit)
    else
      local fprot = game.fluid_prototypes[item_name]
      if fprot ~= nil then
        if item_temp == nil then
          item_temp = fprot.default_temperature
        end
        local key = GlobalState.fluid_temp_key_encode(item_name, item_temp)
        local item_limit = GlobalState.get_limit(key)
        --clog("limit_set_edit_item: fluid [%s] limit=%s", key , item_limit)
        limit_set_edit_type(self, 2)
        self.elems.fluid_elem.elem_value = item_name
        self.elems.temperature.text = string.format("%s", item_temp)
        self.elems.temperature.select(1, 0)
        set_new_limit(self, item_limit)
      end
    end
  end
end

------------------------------------------------------------------------------
-- Event handling below

local function on_group_check_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    self.use_group = not self.use_group
    self:refresh()
  end
end

local function limit_event_prep(event)
  local player = game.get_player(event.player_index)
  if player ~= nil then
    return gui_get(event.player_index)
  end
end

-- the item selection change. refresh the current limit text box
local function on_limit_item_elem_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    limit_set_edit_item(self, self.elems.item_elem.elem_value)
  end
end

-- the fluid selection change. refresh the current limit text box
local function on_limit_fluid_elem_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    limit_set_edit_item(self, self.elems.fluid_elem.elem_value)
  end
end

-- read the limit and save to the limits structure
local function on_limit_save(event)
  local self = limit_event_prep(event)
  if self == nil then
    return
  end
  local edit_flow = self.elems.edit_flow
  local new_limit = self.elems.new_limit.text

  if edit_flow.item_edit.visible then
    -- item
    local item_name = self.elems.item_elem.elem_value
    if item_name ~= nil then
      --clog("setting item %s limit %s", item_name, new_limit)
      if GlobalState.set_limit(item_name, new_limit) then
        self.refresh(self)
      end
    end
  else
    -- fluid
    local fluid_name = self.elems.fluid_elem.elem_value
    local fluid_temp = tonumber(self.elems.temperature.text)
    if fluid_name ~= nil and fluid_temp ~= nil then
      local key = GlobalState.fluid_temp_key_encode(fluid_name, fluid_temp)
      --clog("setting fluid %s limit %s", key, new_limit)
      if GlobalState.set_limit(key, new_limit) then
        self.refresh(self)
      end
    end
  end
end

-- this handles clicking on a limit icon,
-- 1) copies it to the edit layer, picking the right item/fluid
-- 2) clears the limit on right-click
local function on_limit_click_item(event)
  local self = gui_get(event.player_index)
  if self == nil then
    return
  end

  local item_name = event.element.tags.item
  local item_temp = event.element.tags.temp

  if item_name ~= nil then
    -- transfer the existing info to the edit box
    limit_set_edit_item(self, item_name, item_temp)

    if event.button == defines.mouse_button_type.right then
      if game.item_prototypes[item_name] ~= nil then
        GlobalState.clear_limit(item_name)
      elseif item_temp ~= nil and game.fluid_prototypes[item_name] ~= nil then
        local key = GlobalState.fluid_temp_key_encode(item_name, item_temp)
        GlobalState.clear_limit(key)
      end
      self:refresh()
    end
  end
end

-- this handles the change of the fluid/item dropdown
local function on_limit_elem_type(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    limit_set_edit_type(self, self.elems.edit_type.selected_index)
  end
end

-- need to rename to NETLIMIT_ITEM_BTN, NETLIMIT_ITEM_TYPE, NETLIMIT_ITEM_NAME, NETLIMIT_FLUID_NAME, NETLIMIT_SAVE ?
Gui.on_elem_changed(UiConstants.NETLIMIT_SELECT_ITEM, on_limit_item_elem_changed)
Gui.on_elem_changed(UiConstants.NETLIMIT_SELECT_FLUID, on_limit_fluid_elem_changed)
Gui.on_checked_state_changed(UiConstants.NETLIMIT_GROUP, on_group_check_changed)
Gui.on_click(UiConstants.NETLIMIT_SAVE, on_limit_save)
Gui.on_click(UiConstants.NETLIMIT_ITEM_BTN, on_limit_click_item)
Gui.on_selection_state_changed(UiConstants.NETLIMIT_TYPE, on_limit_elem_type)

return M
