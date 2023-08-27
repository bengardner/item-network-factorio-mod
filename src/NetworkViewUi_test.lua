local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local EventDispatch  = require "src.EventDispatch"
local UiCharacterInventory = require "src.UiCharacterInventory"
local UiNetworkItems = require "src.UiNetworkItems"
local log = require("src.log_console").log

local M = {}

M.container_width = 1424
M.container_height = 836

-- hotkey handler
function M.in_open_test_view(event)
  log("in_open_test_view: event.name=%s", event.name)
  M.create_gui(event.player_index)
end

function M.get_gui(player_index)
  return GlobalState.get_ui_state(player_index).test_view
end

--  Destroy the GUI for a player
function M.destroy_gui(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local self = ui.test_view
  if self ~= nil then
    -- break the link to prevent future events
    ui.test_view = nil

    -- call destructor on any child classes
    for _, ch in pairs(self.children) do
      if type(ch.destroy) == "function" then
        ch.destroy(ch)
      end
    end

    local player = self.player
    if player.opened == self.elems.main_window then
      player.opened = nil
    end

    -- destroy the UI
    self.elems.main_window.destroy()
  end
end

--  Create and show the GUI for a player
function M.create_gui(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local old_self = ui.test_view
  if old_self ~= nil then
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
    name = UiConstants.TV_MAIN_FRAME,
    style = "inset_frame_container_frame",
  })
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
    children = {},
  }
  ui.test_view = self
  player.opened = elems.main_window

  self.children.character_inventory = UiCharacterInventory.create(left_pane, player)
  --M.add_character_inventory(self, left_pane)
  self.children.network_items = UiNetworkItems.create(mid_pane, player)
  --M.add_chest_inventory(self, mid_pane)
  M.add_net_inventory(self, right_pane)
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

-- toggles the "pinned" status and updates the window
function M.toggle_pinned(self)
  self.pinned = not self.pinned
  if self.pinned then
    self.elems.close_button.tooltip = { "gui.close" }
    self.elems.pin_button.sprite = "flib_pin_black"
    self.elems.pin_button.style = "flib_selected_frame_action_button"
    if self.player.opened == self.elems.main_window then
      self.player.opened = nil
    end
  else
    self.elems.close_button.tooltip = { "gui.close-instruction" }
    self.elems.pin_button.sprite = "flib_pin_white"
    self.elems.pin_button.style = "frame_action_button"
    self.player.opened = self.elems.main_window
  end
end

function M.on_click_refresh_button(event)
  -- needed to refresh the network item list, which can change rapidly
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    for _, ch in pairs(self.children) do
      if type(ch.refresh) == "function" then
        ch.refresh(ch)
      end
    end
  end
end

function M.on_click_close_button(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.destroy_gui(event.player_index)
  end
end

function M.on_click_pin_button(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.toggle_pinned(self)
  end
end

-- triggered if the GUI is removed from self.player.opened
function M.on_gui_closed(event)
  log("on gui closed")
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    if not self.pinned then
      M.destroy_gui(event.player_index)
    end
  end
end

EventDispatch.add({
  {
    event = "in_open_test_view",
    handler = M.in_open_test_view,
  },
  {
    name = UiConstants.TV_PIN_BTN,
    event = "on_gui_click",
    handler = M.on_click_pin_button,
  },
  {
    name = UiConstants.TV_CLOSE_BTN,
    event = "on_gui_click",
    handler = M.on_click_close_button,
  },
  {
    name = UiConstants.TV_REFRESH_BTN,
    event = "on_gui_click",
    handler = M.on_click_refresh_button,
  },
  {
    name = UiConstants.TV_MAIN_FRAME,
    event = "on_gui_closed",
    handler = M.on_gui_closed,
  },
})

return M
