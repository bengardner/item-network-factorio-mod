--[[
  Creates the Network invetory GuiElement tree under the specified parent GuiElement.
  There can be only one per character,
]]
local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local EventDispatch  = require "src.EventDispatch"
local item_utils = require "src.item_utils"

local M = {}
local NetInv = {}

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiNetworkItems
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiNetworkItems = value
end

function M.create(parent, player, show_title)
  local self = {
    player = player,
    elems = {},
    use_group = true,
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
    name = UiConstants.NETITEM_GROUP,
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
  self.elems.table_network_items = item_table

  gui_set(player.index, self)

  -- populate the table
  self:refresh()

  return self
end

function NetInv.destroy(self)
  gui_set(self.player.index, nil)
end

local function get_list_of_items()
  local items = {}

  local function add_item(item)
    if game.item_prototypes[item.item] ~= nil or game.fluid_prototypes[item.item] ~= nil then
      table.insert(items, item)
    end
  end

  local items_to_display = GlobalState.get_items()
  for item_name, item_count in pairs(items_to_display) do
    if item_count > 0 then
	    add_item({ item = item_name, count = item_count })
    end
  end

  return item_utils.entry_list_split_by_group(items)
end

function M.get_sprite_button_def(item)
  local tooltip
  local sprite_path
  local tags
  if item.temp == nil then
    tooltip = item_utils.get_item_tooltip(item.item, item.count)
    tags = { event = UiConstants.NETITEM_ITEM, item = item.item }
    sprite_path = "item/" .. item.item
  else
    tooltip = item_utils.get_fluid_tooltip(item.item, item.temp, item.count)
    sprite_path = "fluid/" .. item.item
  end
  return {
    type = "sprite-button",
    sprite = sprite_path,
    tooltip = tooltip,
    tags = tags,
  }
end

function NetInv.refresh(self)
  local item_table = self.elems.table_network_items
  item_table.clear()

  local total_items = 0
  local total_count = 0
  local use_group = self.use_group

  -- add a dummy slot for dropping stuff
  item_table.add({
    type = "sprite-button",
    sprite = "utility/slot_icon_resource_black",
    style = "inventory_slot",
    tags = { event = UiConstants.NETITEM_SLOT },
    tooltip = { "in_nv.deposit_item_sprite_btn_tooltip" },
  })

  if use_group then
    item_utils.pad_item_table_row(item_table)
  end

  -- add the items
  local items = get_list_of_items()
  for _, item in ipairs(items) do
    if type(item) ~= "table" then
      if use_group then
        item_utils.pad_item_table_row(item_table)
      end
    else
      local sprite_button = M.get_sprite_button_def(item)
      local sprite_button_inst = item_table.add(sprite_button)
      sprite_button_inst.number = item.count
      total_items = total_items + 1
      total_count = total_count + item.count
    end
  end
  if use_group then
    item_utils.pad_item_table_row(item_table)
  end

  self.elems.title.caption = string.format("Network Items - %s items, %s total", total_items, total_count)
end

--[[
  This handles a click on an item sprite in the item view.
  If the cursor has something in it, then the cursor content is dumped into the item network.
  If the cursor is empty then we grab something from the item network.
    left-click grabs one item.
    shift + left-click grabs one stack.
    ctrl + left-click grabs it all.
]]
local function NetInv_click_slot(self, event)
  local player = self.player
  local inv = player.get_main_inventory()
  if inv == nil then
    return
  end
  local element = event.element
  if element == nil or not element.valid then
    return
  end

  local something_changed = false

  -- if we have an empty cursor, then we are taking items, which requires a valid target
  if player.is_cursor_empty() then
    local item_name = event.element.tags.item
    if item_name == nil then
      return
    end

    local network_count = GlobalState.get_item_count(item_name)
    local stack_size = game.item_prototypes[item_name].stack_size

    if event.button == defines.mouse_button_type.left then
      -- shift moves a stack, non-shift moves 1 item
      local n_transfer = 1
      if event.shift then
        n_transfer = stack_size
      elseif event.control then
        n_transfer = network_count
      end
      -- move one item or stack to player inventory
      n_transfer = math.min(network_count, n_transfer)
      if n_transfer > 0 then
        local n_moved = inv.insert({ name = item_name, count = n_transfer })
        if n_moved > 0 then
          GlobalState.set_item_count(item_name, network_count - n_moved)
          local count = GlobalState.get_item_count(item_name)
          element.number = count
          element.tooltip = item_utils.get_item_tooltip(item_name, count)
          something_changed = true
        end
      end
    end
  else
    -- There is a stack in the cursor. Deposit it.
    local cursor_stack = player.cursor_stack
    if not cursor_stack or not cursor_stack.valid_for_read then
      return
    end

    -- don't deposit tracked entities (can be unique)
    if cursor_stack.item_number ~= nil then
      game.print(string.format(
        "Unable to deposit %s because it might be a vehicle with items that will be lost.",
        cursor_stack.name))
      return
    end

    if event.button == defines.mouse_button_type.left then
      local item_name = cursor_stack.name

      -- move the stack to the item network
      GlobalState.increment_item_count(item_name, cursor_stack.count)
      cursor_stack.count = 0
      cursor_stack.clear()
      player.clear_cursor()
      something_changed = true

      -- if control is pressed, move all of that item to the network
      if event.control then
        local my_count = inv.get_item_count(item_name)
        if my_count > 0 then
          GlobalState.increment_item_count(item_name, my_count)
          inv.remove({name=item_name, count=my_count})
        end
      end
    end
  end

  if something_changed then
    --player.play_sound{path = "utility/inventory_click"}
    self:refresh()
  end
end

local function on_click_net_inv_slot(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    NetInv_click_slot(self, event)
  end
end

local function on_group_check_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    self.use_group = not self.use_group
    self:refresh()
  end
end

EventDispatch.add({
  {
    name = UiConstants.NETITEM_ITEM,
    event = "on_gui_click",
    handler = on_click_net_inv_slot,
  },
  {
    name = UiConstants.NETITEM_SLOT,
    event = "on_gui_click",
    handler = on_click_net_inv_slot,
  },
  {
    name = UiConstants.NETITEM_GROUP,
    event = "on_gui_checked_state_changed",
    handler = on_group_check_changed,
  },
})

return M
