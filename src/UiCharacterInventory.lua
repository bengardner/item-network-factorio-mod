--[[
  Creates a character invetory GuiElement tree under the specified parent GuiElement.
  There can be only one per character,

  Inteface for the module:
  - M.create(parent, player)
    Create the GUI element tree as a child of @parent for @player

  Exposed interface for the "instance"
  - inst.frame (R)
    This is the top-most GUI element. Useful to assign to a tabbed pane.

  - inst.peer (R/W)
    This is the target for inventory operations.
    The peer must provide one function:
      peer:insert(ItemStackIdentification) => n_inserted
        - SHIFT + left => transfer one item stack to peer
        - SHIFT + right => transfers min(ceil(net_count/2), ceil(stack_size/2)) to peer
        - CTRL + left => transfer all item to peer
        - CTRL + right => transfer half of items (ceil(net_count/2)) to peer
    This field is only checked when trying to move inventory to the peer.

  - inst:insert(ItemStackIdentification) => n_inserted
    Called to insert items into this control.
    Maps directly to a call to player.insert(...).
    IE, ammo might go to the ammo inventory, other to the main inv.

  - inst:destroy()
    This destroys any data associated with the instance and the GUI.

  - inst:refresh()
    This refreshes the data in the display.

]]
local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local clog = require("src.log_console").log
local item_utils = require("src.item_utils")

local M = {}
local CharInv = {}

local CharInv__metatable = {
  __index = CharInv
}
script.register_metatable("CharInv", CharInv__metatable)

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiCharacterInventory
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiCharacterInventory = value
end

function M.create(parent, player)
  local self = {
    player = player,
    elems = {},
  }

  -- set index so we can call self:refresh() or M.refresh(self)
  setmetatable(self, CharInv__metatable)

  --[[
  GuiElement Layout:

  + parent
    + flow-vertical
      + frame [character_inventory_frame]
        + scroll-pane [character_inventory_scroll_pane]
          + flow-horizontal
            + label [inventory_label] "Character"
          + table [slot_table]
  ]]

  local vert_flow = parent.add({
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

  gui_set(player.index, self)

  -- populate the table
  self:refresh()

  return self
end

function CharInv.destroy(self)
  gui_set(self.player.index, nil)
end

function CharInv.refresh(self)
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
        name = string.format("%s:%s", UiConstants.CHARINV_HAND, idx),
        type = "sprite-button",
        sprite = "utility/hand",
        hovered_sprite = "utility/hand_black",
        clicked_sprite = "utility/hand_black",
        style = "inventory_slot",
        tags = { event = UiConstants.CHARINV_HAND, slot = idx },
      })
    elseif stack.valid_for_read then
      local inst = item_table.add({
        name = string.format("%s:%s", UiConstants.CHARINV_ITEM, idx),
        type = "sprite-button",
        sprite = "item/" .. stack.name,
        style = "inventory_slot",
        tags = { event = UiConstants.CHARINV_ITEM, slot = idx },
      })
      inst.tooltip = item_utils.get_item_char_inventory_tooltip(stack.name, stack.count)
      inst.number = stack.count
    else
      item_table.add({
        name = string.format("%s:%s", UiConstants.CHARINV_SLOT, idx),
        type = "sprite-button",
        sprite = "utility/slot_icon_resource",
        style = "inventory_slot",
        tags = { event = UiConstants.CHARINV_SLOT, slot = idx },
      })
    end
  end
end

function CharInv:insert(items)
  return self.player.insert(items)
end

--[[
  Handles the on_gui_click event for all main character inventory slots.
  The element has tags.slot set to the slot index that was clicked.
  The stack for that slot is inv[slot].
]]
local function charinv_click_slot(self, event)
  local element = event.element
  if element == nil or element.tags.slot == nil then
    return
  end
  local player = self.player
  local inv = player.get_main_inventory()
  local slot = element.tags.slot
  local stack = inv[slot]

  -- Standard mouse clicks:
  -- left click => pick up / drop stack
  -- right click => pick up half-stack
  -- shift + left => transfer stack to "other" inventory
  -- control + left => transfer all to "other" inventory
  -- shift + right => transfer half stack
  -- control + right => hald transfer
  -- middle mouse => create filter on slot
  local mods = 0
  if event.alt then
    mods = mods + 1
  end
  if event.control then
    mods = mods + 2
  end
  if event.shift then
    mods = mods + 4
  end
  local play_sound = false

  --[[
  peer:insert({name=name, count=count}) => n_inserted
  - SHIFT + left => transfer one item stack to peer
  - SHIFT + right => transfers min(ceil(net_count/2), ceil(stack_size/2)) to peer
  - CTRL + left => transfer all item to peer
  - CTRL + right => transfer half of items (ceil(net_count/2)) to peer
  ]]

  if event.button == defines.mouse_button_type.left then
    if mods == 4 then
      if stack.valid_for_read and self.peer and self.peer.insert then
        -- SHIFT + Left click : transfer stack to peer
        local n_added = self.peer:insert(stack)
        if n_added > 0 and stack.valid_for_read then
          stack.count = stack.count - n_added
        end
        play_sound = true
      end

    elseif mods == 2 then
      -- CTRL + Left click => transfer all item to peer
      if stack.valid_for_read and self.peer and self.peer.insert then
        local item_name = stack.name
        for idx = 1, #inv do
          local st = inv[idx]
          if st.valid_for_read and st.name == item_name then
            local n_added = self.peer:insert(st)
            if n_added > 0 and st.valid_for_read then
              st.count = st.count - n_added
            end
            play_sound = true
          end
        end
      end

    elseif mods == 0 then
      -- no shift: drop and then pick up the stack

      -- drop the cursor content into the player inventory
      if not player.is_cursor_empty() then
        -- drop cursor contents into the inventory
        local n_added = inv.insert(player.cursor_stack)
        if n_added > 0 then
          play_sound = true
          if player.cursor_stack.valid_for_read then
            player.cursor_stack.count = player.cursor_stack.count - n_added
          end
        end
      end

      -- pick up the inventory in the slot
      if player.is_cursor_empty() and event.match == UiConstants.CHARINV_ITEM and stack.valid_for_read then
        player.cursor_stack.transfer_stack(stack)
        self.player.hand_location = { inventory = inv.index, slot = slot }
        play_sound = true
      end
    end

  elseif event.button == defines.mouse_button_type.right then
    -- right click with an empty stack grabs half the stack
    if player.is_cursor_empty() and stack.valid_for_read then
      -- special case to preserve any custom item data (grid)
      if stack.count == 1 then
        player.cursor_stack.transfer_stack(stack)
      else
        local half_count = math.ceil(stack.count / 2)
        player.cursor_stack.set_stack({ name=stack.name, count=half_count })
        stack.count = stack.count - half_count -- might set to 0, invalidating the stack
      end
      play_sound = true
    end
  end
  if play_sound then
    player.play_sound{path = "utility/inventory_click"}
  end
end

local function on_click_char_inv_slot(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    charinv_click_slot(self, event)
  end
end

local function on_player_main_inventory_or_cursor_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil and self.refresh ~= nil then
    self:refresh()
  end
end

Event.on_event(
  {
    defines.events.on_player_main_inventory_changed,
    defines.events.on_player_cursor_stack_changed,
  },
  on_player_main_inventory_or_cursor_changed
)

Gui.on_click(UiConstants.CHARINV_ITEM, on_click_char_inv_slot)
Gui.on_click(UiConstants.CHARINV_HAND, on_click_char_inv_slot)
Gui.on_click(UiConstants.CHARINV_SLOT, on_click_char_inv_slot)

return M
