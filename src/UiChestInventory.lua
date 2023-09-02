--[[
  Creates a chest invetory GuiElement tree under the specified parent GuiElement.

  Inteface for the module:
  - M.create(parent, player, chest, args)
    Create the GUI element tree as a child of @parent for @player
    - parent : parent GUI element
    - player : the owning player (for the GUI)
    - chest  : chest info structure / entity data
    - args:
      "read_only" = bool
        disconnect events if true
      ""

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
local ChestInv = {}

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiChestInventory
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiChestInventory = value
end

function M.create(parent, player, entity)
  local self = {
    player = player,
    elems = {},
    entity = entity,
  }

  -- set index so we can call self:refresh() or M.refresh(self)
  setmetatable(self, { __index = ChestInv })

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
    caption = entity.localised_name,
    style = "inventory_label",
  })

  local entity_preview = scroll_pane.add({
    type = "entity-preview",
    style = "wide_entity_button",
  })
  entity_preview.style.horizontally_stretchable = true
  entity_preview.style.minimal_width = 400
  entity_preview.style.natural_height = 148
  entity_preview.style.height = 148
  entity_preview.entity = entity

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

function ChestInv.destroy(self)
  gui_set(self.player.index, nil)
end

local function get_localised_item(name)
  local prot = game.item_prototypes[name]
  if prot ~= nil then
    return prot.localised_name
  end
  return name
end

-- Filters don't work when mixed.
function ChestInv.refresh(self)
  local item_table = self.elems.table_character_inventory
  item_table.clear()

  local inv = self.entity.get_output_inventory()
  if inv == nil then
    return
  end
  local bar_idx = #inv + 1
  if inv.supports_bar() then
    bar_idx = inv.get_bar()
  end
  local bar_active = bar_idx <= #inv

  local mouse_button_filter = { "left", "right", "middle" }

  for idx = 1, #inv do
    local stack = inv[idx]
    local style
    local filt = inv.get_filter(idx)
    if idx >= bar_idx then
      style = "closed_inventory_slot"
    elseif filt ~= nil then
      style = "filter_inventory_slot"
    else
      style = "inventory_slot"
    end
    if stack.valid_for_read then
      local inst = item_table.add({
        name = string.format("%s:%s", UiConstants.CHESTINV_ITEM, idx),
        type = "sprite-button",
        sprite = "item/" .. stack.name,
        style = style,
        tags = { event = UiConstants.CHESTINV_ITEM, slot = idx },
        raise_hover_events = (self.set_bar_slot ~= nil),
        mouse_button_filter = mouse_button_filter,
      })
      inst.tooltip = item_utils.get_item_plain_tooltip(stack.name, stack.count)
      inst.number = stack.count
    elseif filt ~= nil then
      local ent = item_table.add({
        name = string.format("%s:%s", UiConstants.CHESTINV_SLOT, idx),
        type = "sprite-button",
        sprite = "item/" .. filt,
        style = style,
        tags = { event = UiConstants.CHESTINV_SLOT, slot = idx },
        raise_hover_events = (self.set_bar_slot ~= nil),
        mouse_button_filter = mouse_button_filter,
      })
      ent.tooltip = item_utils.get_item_filter_tooltip(filt)
    else
      local ent = item_table.add({
        name = string.format("%s:%s", UiConstants.CHESTINV_SLOT, idx),
        type = "sprite-button",
        sprite = "utility/slot_icon_resource",
        style = style,
        tags = { event = UiConstants.CHESTINV_SLOT, slot = idx },
        raise_hover_events = (self.set_bar_slot ~= nil),
        mouse_button_filter = mouse_button_filter,
      })
    end
  end
  -- add the "X"
  -- if chest has bar then
  if inv.supports_bar() then
    item_table.add({
      name = UiConstants.CHESTINV_BAR,
      type = "sprite-button",
      sprite = "utility/set_bar_slot",
      style = "inventory_limit_slot_button",
      tags = { event = UiConstants.CHESTINV_BAR },
      auto_toggle = false,
      toggled = (self.set_bar_slot ~= nil or bar_active),
    })
  end
end

function ChestInv:insert(items)
  return self.player.insert(items)
end

--[[
  Handles the on_gui_click event for all main character inventory slots.
  The element has tags.slot set to the slot index that was clicked.
  The stack for that slot is inv[slot].
]]
local function chestinv_click_slot(self, event)
  local element = event.element
  if element == nil or element.tags.slot == nil then
    return
  end
  local entity = self.entity
  if entity == nil or not entity.valid then
    return
  end
  local player = self.player
  local inv = entity.get_output_inventory()
  local slot = element.tags.slot
  local stack = inv[slot]

  if self.set_bar_slot ~= nil then
    inv.set_bar(slot)
    self.set_bar_slot = nil
    self:refresh()
    return
  end

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

      -- if something is in the cursor, we will combine or swap
      if not player.is_cursor_empty() then
        -- if same as the target we combine and shift inv
        local cstack = player.cursor_stack
        if stack.valid_for_read and stack.name == cstack.name then
          local prot = game.item_prototypes[stack.name]
          if prot ~= nil then
            local n_move = math.min(prot.stack_size - stack.count, cstack.count)
            if n_move > 0 then
              stack.count = stack.count + n_move
              cstack.count = cstack.count - n_move
              play_sound = true
            end
          end
        else
          -- swap inventory with cursor
          stack.swap_stack(cstack)
          play_sound = true
        end
      else
        -- pick up the inventory in the slot
        if event.match == UiConstants.CHESTINV_ITEM and stack.valid_for_read then
          player.cursor_stack.transfer_stack(stack)
          --self.player.hand_location = { inventory = inv.index, slot = slot }
          play_sound = true
        end
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
  elseif event.button == defines.mouse_button_type.middle then
    clog("middle-click on slot %s", slot)
  end
  if play_sound then
    player.play_sound{path = "utility/inventory_click"}
    self:refresh()
  end
end

--[[
  Handles the on_gui_click event for all main character inventory slots.
  The element has tags.slot set to the slot index that was clicked.
  The stack for that slot is inv[slot].
]]
local function chestinv_hover_slot(self, event)
  local element = event.element
  if element == nil or element.tags.slot == nil or not self.entity.valid then
    return
  end
  local inv = self.entity.get_output_inventory()
  local slot = element.tags.slot

  if self.set_bar_slot ~= slot then
    inv.set_bar(slot)
    self.set_bar_slot = slot
    self:refresh()
  end
end

local function on_click_chest_inv_slot(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    chestinv_click_slot(self, event)
  end
end

-- Starts or abandons the bar selection (click on red X button)
local function on_click_chest_bar_slot(event)
  local self = gui_get(event.player_index)
  if self ~= nil and self.entity and self.entity.valid then
    local inv = self.entity.get_output_inventory()
    if inv ~= nil then
      if self.set_bar_slot ~= nil or inv.get_bar() <= #inv then
        -- cancel active selection
        self.set_bar_slot = nil
        inv.set_bar()
      else
        -- start a new bar selection
        self.set_bar_slot = inv.get_bar()
      end
      self:refresh()
    end
  end
end

local function on_hover_chest_inv_slot(event)
  local self = gui_get(event.player_index)
  if self ~= nil and self.set_bar_slot ~= nil then
    chestinv_hover_slot(self, event)
  end
end

local function on_filter_chest_inv_slot(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    local element = event.element
    if element == nil or element.tags.slot == nil then
      return
    end
    local entity = self.entity
    if entity == nil or not entity.valid then
      return
    end
    local inv = entity.get_output_inventory()
    local slot = element.tags.slot

    clog("filtered: slot %s to %s", slot, element.elem_value)
    inv.set_filter(slot, element.elem_value)
    self:refresh()
  end
end

Gui.on_click(UiConstants.CHESTINV_ITEM, on_click_chest_inv_slot)
Gui.on_click(UiConstants.CHESTINV_SLOT, on_click_chest_inv_slot)
Gui.on_click(UiConstants.CHESTINV_BAR, on_click_chest_bar_slot)
Gui.on_elem_changed(UiConstants.CHESTINV_ITEM, on_filter_chest_inv_slot)
Gui.on_elem_changed(UiConstants.CHESTINV_SLOT, on_filter_chest_inv_slot)
Event.register(defines.events.on_gui_hover, on_hover_chest_inv_slot, Event.Filters.gui, UiConstants.CHESTINV_SLOT)
Event.register(defines.events.on_gui_hover, on_hover_chest_inv_slot, Event.Filters.gui, UiConstants.CHESTINV_ITEM)

return M
