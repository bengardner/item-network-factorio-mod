--[[
  Creates a character invetory GuiElement tree under the specified parent GuiElement.
  There can be only one per character,

  TODO: add a "set_peer" function that will set a peer class. That will provide an "insert" function.

      other:insert(name, count)

      That would allow "normal" interactions with the character inventory.
]]
local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')

local M = {}
local CharInv = {}

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
  setmetatable(self, { __index = CharInv })

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
  --
  local play_sound = false

  if event.button == defines.mouse_button_type.left then
    -- drop the cursor content into the player inventory
    if not player.is_cursor_empty() then
      -- drop cursor contents into the inventory
      inv.insert({name = player.cursor_stack.name, count = player.cursor_stack.count})
      player.cursor_stack.clear()
      play_sound = true
    end

    -- pick up the inventory in the slot
    if event.match == UiConstants.CHARINV_ITEM and stack.valid_for_read then
      player.cursor_stack.transfer_stack(inv[slot])
      self.player.hand_location = { inventory = inv.index, slot = slot }
      play_sound = true
    end

  elseif event.button == defines.mouse_button_type.right then
    -- right click with an empty stack grabs half the stack
    if player.is_cursor_empty() and stack.valid_for_read then
      local half_count = math.ceil(stack.count / 2)
      player.cursor_stack.set_stack({ name=stack.name, count=half_count })
      stack.count = stack.count - half_count -- might set to 0, invalidating the stack
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
  if self ~= nil then
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
