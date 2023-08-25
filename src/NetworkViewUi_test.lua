local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local EventDispatch  = require "src.EventDispatch"

local M = {}

M.container_width = 1424
M.container_height = 836

-- hotkey handler
function M.in_open_test_view(event)
  M.create_gui(event.player_index)
end

function M.get_gui(player_index)
  return GlobalState.get_ui_state(player_index).test_view
end

--  Destroy the GUI for a player
function M.destroy_gui(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  if ui.test_view ~= nil then
    ui.test_view.elems.main_window.destroy()
    ui.test_view = nil
  end
end

--  Create and show the GUI for a player
function M.create_gui(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  if ui.test_view ~= nil then
    -- hotkey toggles the GUI
    M.destroy_gui(player_index)
    return
  end

  local player = game.get_player(player_index)
  if player == nil then
    return
  end

  -- important elements are stored here
  --   main_window
  --   ??
  local elems = {}

  -- create the main window
  elems.main_window = player.gui.screen.add({
    type = "frame",
    name = UiConstants.NV_FRAME,
    style = "inset_frame_container_frame",
  })
  player.opened = elems.main_window
  elems.main_window.auto_center = true
  elems.main_window.style.horizontally_stretchable = true
  elems.main_window.style.vertically_stretchable = true

  local vert_flow = elems.main_window.add({
    type = "flow",
    direction = "vertical",
  })

  -- add the header/toolbar
  local header_flow = vert_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  header_flow.drag_target = elems.main_window

  header_flow.add {
    type = "label",
    caption = "Item Network Test Window",
    style = "frame_title",
    ignored_by_interaction = true,
  }

  local header_drag = header_flow.add {
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true,
  }
  header_drag.style.horizontally_stretchable = true
  header_drag.style.vertically_stretchable = true

  header_flow.add {
    type = "sprite-button",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = { "gui.refresh" },
    tags = { event = UiConstants.TV_REFRESH_BTN },
  }

  elems.close_button = header_flow.add {
    name = "close_button",
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
    tags = { event = UiConstants.TV_CLOSE_BTN },
  }

  elems.pin_button = header_flow.add {
    name = "pin_button",
    type = "sprite-button",
    sprite = "flib_pin_white",
    hovered_sprite = "flib_pin_black",
    clicked_sprite = "flib_pin_black",
    style = "frame_action_button",
    tags = { event = UiConstants.TV_PIN_BTN },
  }

  -- add shared body area
  local body_flow = vert_flow.add({
    type = "flow",
    direction = "horizontal",
  })

  -- dummy flow to be the parent of the character inventory
  local left_pane = body_flow.add({
    type = "flow",
  })
  -- testing if I actually need this size or if it will adjust
  --left_pane.style.size = { 464, 828 }

  local mid_pane = body_flow.add({
    type = "flow",
    --type = "frame",
    --style = "frame_without_left_and_right_side",
  })
  mid_pane.style.size = { 467, 828 }

  local right_pane = body_flow.add({
    type = "flow",
    --type = "frame",
    --style = "frame_without_left_side",
  })
  right_pane.style.size = { 476, 828 }

  local self = {
    elems = elems,
    pinned = false,
    player = player,
  }
  ui.test_view = self

  M.add_character_inventory(self, left_pane)
  M.add_chest_inventory(self, mid_pane)
  M.add_net_inventory(self, right_pane)
end

function M.add_character_inventory(self, frame)
  local vert_flow = frame.add({
    type = "flow",
    direction = "vertical",
  })
  local inv_frame = vert_flow.add({
    type = "frame",
    style = "character_inventory_frame",
  })
  local scroll_pane = inv_frame.add({
    type = "scroll-pane",
    style = "character_inventory_scroll_pane",
  }) -- 424, 728 or 400,712
  scroll_pane.style.width = 424

  --[[
Looks like:
character_gui_left_side
character_inventory_scroll_pane
scroll_pane
  + horizontal_flow (400 x 28)
     + slot_button_that_fits_textline
     + color_indicator
  +
  ]]
  local hdr = scroll_pane.add({
    type = "flow",
    direction = "horizontal",
  })
  hdr.style.size = { 400, 28 }

  hdr.add({
    type = "label",
    caption = "Character",
    style = "inventory_label",
  })

  local item_table = scroll_pane.add({
    type = "table",
    name = "item_table",
    style = "slot_table",
    column_count = 10
  })
  self.elems.table_character_inventory = item_table

  M.refresh_character_inventory(self)
end

function M.refresh_character_inventory(self)
  local item_table = self.elems.table_character_inventory
  item_table.clear()

  local inv = self.player.get_main_inventory()
  if inv == nil then
    return
  end
  inv.sort_and_merge()

 -- draw the hand instead of a blank entry if reasons
  local hand_slot = 0
  if self.player.hand_location ~= nil and inv.index == self.player.hand_location.inventory then
    hand_slot = self.player.hand_location.slot
  end

  for idx = 1, #inv do
    local stack = inv[idx]
    if idx == hand_slot then
      item_table.add({
        type = "sprite-button",
        sprite = "utility/hand",
        hovered_sprite = "utility/hand_black",
        clicked_sprite = "utility/hand_black",
        style = "inventory_slot",
        tags = { event = UiConstants.CHARINV_HAND, slot = idx },
      })
    elseif stack.valid_for_read then
      local inst = item_table.add({
        type = "sprite-button",
        sprite = "item/" .. stack.name,
        style = "inventory_slot",
        tags = { event = UiConstants.CHARINV_ITEM, item = stack.name, slot = idx },
      })
      inst.number = stack.count
    else
      item_table.add({
        type = "sprite-button",
        sprite = "utility/slot_icon_resource",
        style = "inventory_slot",
        tags = { event = UiConstants.CHARINV_SLOT, slot = idx },
      })
    end
  end
end

function M.add_chest_inventory(self, frame)
  local vert_flow = frame.add({
    type = "frame",
    style = "character_inventory_frame",
  })
end

function M.add_net_inventory(self, frame)
end


--[[

frame: (invisible frame)
  horizontal_flow
    [character] - frame style character_gui_left_side
      464, 828
      [horizontal_flow]
        [frame_title]
        [ draggable_space_header]
        [search_bar_horizontal_flow]
          [frame_action_button - search]
        [frame_action_button - style close_button]

    [chest] - frame style "frame_without_left_and_right_side"
      467, 828
    [network items] - frame style "frame_without_left_and_right_side"
      476, 828
      [horizontal_flow]
        [frame_title]
        [ draggable_space_header]
        [search_bar_horizontal_flow]
          [frame_action_button - search]
        [frame_action_button - style close_button]


]]

function M.charinv_click_item(self, event)
  local element = event.element
  if element == nil then
    return
  end
  local player = self.player
  local inv = player.get_main_inventory()

  -- log the event
  local ctext = "cursor is empty"
  if not player.is_cursor_empty() then
    ctext = string.format("cursor name=%s count=%s", player.cursor_stack.name, player.cursor_stack.count)
  end
  game.print(string.format("Clicked on slot %s [%s] button=%s alt=%s control=%s shift=%s - %s",
    element.tags.slot, element.tags.item,
    event.button, event.alt, event.control, event.shift, ctext))

  -- left click => pick up / drop stack
  -- right click => pick up half-stack
  -- shift + left => transfer stack to "other" inventory
  -- control + left => transfer all to "other" inventory
  -- shift + right => transfer half stack
  -- control + right => hald transfer
  -- middle mouse => create filter on slot
  --

  if event.button == defines.mouse_button_type.left then
    if not player.is_cursor_empty() then
      -- drop cursor into inventory
      inv.insert({name = player.cursor_stack.name, count = player.cursor_stack.count})
      player.cursor_stack.clear()
    end
    if element.tags.item ~= nil then
      player.cursor_stack.transfer_stack(inv[element.tags.slot])
      self.player.hand_location = { inventory = inv.index, slot = element.tags.slot }
    end
  elseif event.button == defines.mouse_button_type.right then
    -- right click with an empty stack grabs half the stack
    if player.is_cursor_empty() and element.tags.item ~= nil then
      local stack = inv[element.tags.slot]
      if stack.valid_for_read then
        local half_count = math.ceil(stack.count / 2)
        player.cursor_stack.set_stack({ name=stack.name, count=half_count })
        stack.count = stack.count - half_count
      end
    end
  end
end

function M.charinv_click_hand(self, event)
  local player = self.player
  if player.is_cursor_empty() then
  else
  end
end

function M.charinv_click_slot(self, event)
  local player = self.player
  if player.is_cursor_empty() then
  else
  end
end

function M.on_click_char_inv_item(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.charinv_click_item(self, event)
  end
end

function M.on_click_char_inv_hand(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.charinv_click_item(self, event)
  end
end

function M.on_click_char_inv_slot(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.charinv_click_item(self, event)
  end
end

function M.on_player_main_inventory_changed(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    game.print("on_player_main_inventory_changed")
    M.refresh_character_inventory(self)
  end
end

function M.on_player_cursor_stack_changed(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    game.print("on_player_cursor_stack_changed")
    M.refresh_character_inventory(self)
  end
end

EventDispatch.add(
  defines.events.on_player_main_inventory_changed,
  M.on_player_main_inventory_changed
)

EventDispatch.add(
  defines.events.on_player_cursor_stack_changed,
  M.on_player_cursor_stack_changed
)

return M
