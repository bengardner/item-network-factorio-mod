local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local UiCharacterInventory = require "src.UiCharacterInventory"
local UiNetworkItems = require "src.UiNetworkItems"
local UiChestInventory = require "src.UiChestInventory"
local clog = require("src.log_console").log
local auto_player_request = require'src.auto_player_request'

local M = {}

M.container_width = 1424
M.container_height = 836

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
  vert_flow.style.horizontally_stretchable = true
  vert_flow.style.vertically_stretchable = true

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
    name = UiConstants.TV_REFRESH_BTN,
    type = "sprite-button",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = { "gui.refresh" },
  }

  elems.close_button = header_flow.add {
    name = UiConstants.TV_CLOSE_BTN,
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
  }

  elems.pin_button = header_flow.add {
    name = UiConstants.TV_PIN_BTN,
    type = "sprite-button",
    sprite = "flib_pin_white",
    hovered_sprite = "flib_pin_black",
    clicked_sprite = "flib_pin_black",
    style = "frame_action_button",
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
  --mid_pane.style.size = { 467, 828 }


  local right_pane = body_flow.add({
    type = "flow",
  })
  --right_pane.style.size = { 476, 828 }

  local self = {
    elems = elems,
    pinned = false,
    player = player,
    children = {},
  }
  ui.test_view = self
  player.opened = elems.main_window

  self.children.character_inventory = UiCharacterInventory.create(left_pane, player)
  self.children.network_items = UiNetworkItems.create(mid_pane, player)

  -- cross-link to try inventory transfers
  self.children.character_inventory.peer = self.children.network_items
  self.children.network_items.peer = self.children.character_inventory

  --[[ test
  for _, info in pairs(GlobalState.get_chests()) do
    local entity = info.entity
    if entity and entity.valid and entity.name == "network-chest-requester" then
      self.children.chest_inv = UiChestInventory.create(right_pane, player, entity)
      break
    end
  end
  ]]
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
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    if not self.pinned then
      M.destroy_gui(event.player_index)
    end
  end
end

local function recurse_find_damage(tab)
  if tab.type == 'damage' and tab.damage ~= nil then
    return tab.damage
  end
  for k, v in pairs(tab) do
    if type(v) == 'table' then
      local rv = recurse_find_damage(v)
      if rv ~= nil then
        return rv
      end
    end
  end
  return nil
end

local function log_ammo_stuff()
  --local fuels = {} -- array { name, energy per stack }
  local ammo_list = {}
  for _, prot in pairs(game.item_prototypes) do
    if prot.type == "ammo" then
      print("-")
      clog("ammo: %s type=%s attack=%s", prot.name, prot.type, serpent.line(prot.attack_parameters))

      local at = prot.get_ammo_type()
      if at ~= nil then
        clog(" - category %s", tt, serpent.line(at.category))
        if at.category == 'bullet' then
          local damage = recurse_find_damage(at.action)
          if damage ~= nil and type(damage.amount) == "number" then
            clog(" - damage %s", damage.amount)

            local xx = ammo_list[at.category]
            if xx == nil then
              xx = {}
              ammo_list[at.category] = xx
            end
            table.insert(xx, { name=prot.name, amount=damage.amount })
          end
        end
      end
    end
    if prot.type == "gun" then
      print("-")
      clog("gun: %s type=%s attack=%s", prot.name, prot.type, serpent.line(prot.attack_parameters))

      --[[
      for _, tt in ipairs({ "default", "player", "turret", "vehicle"}) do
        local at = prot.get_ammo_type(tt)
        if at ~= nil then
          clog(" - %s => %s", tt, serpent.line(at.category))
          local xx = ammo_list[at.category]
          if xx == nil then
            xx = {}
            ammo_list[at.category] =xx
          end
          xx[prot.name] = true
        end
      end
      ]]
    end
  end
  for k, xx in pairs(ammo_list) do
    table.sort(xx, function (a, b) return a.amount > b.amount end)
  end
  clog("####   ammo: %s", serpent.line(ammo_list))

  for _, prot in pairs(game.entity_prototypes) do
    local guns = prot.guns
    if guns ~= nil then
      clog(" - %s has guns => %s", prot.name, serpent.line(guns))
      for idx, ig in pairs(prot.indexed_guns) do
        local ap = ig.attack_parameters
        local ac = ap.ammo_categories
        clog("  ++ %s %s %s :: %s", idx, ig.name, ig.type, serpent.line(ig.attack_parameters.ammo_categories))
        --clog("   =>> ap %s", serpent.line(ap))
        for k, v in pairs(ac) do
          clog("   =>> ac %s = %s", serpent.line(k), serpent.line(v))
        end
      end
    end
  end
end

Gui.on_click(UiConstants.TV_PIN_BTN, M.on_click_pin_button)
Gui.on_click(UiConstants.TV_CLOSE_BTN, M.on_click_close_button)
Gui.on_click(UiConstants.TV_REFRESH_BTN, M.on_click_refresh_button)
-- Gui doesn't have on_gui_closed, so add it manually
Event.register(defines.events.on_gui_closed, M.on_gui_closed, Event.Filters.gui, UiConstants.TV_MAIN_FRAME)

-- hotkey handler
Event.on_event("in_open_test_view", function (event)
    M.create_gui(event.player_index)
  end)


Event.on_event("debug-network-item", function (event)
    --GlobalState.log_queue_info()
    -- log_ammo_stuff()
    --[[ player_index, input_name, cursor_position, ]]
    local player = game.get_player(event.player_index)
    if player ~= nil and player.selected then
      local ent = player.selected
      local unum = ent.unit_number
      clog("EVENT %s ent=[%s] %s %s", serpent.line(event), unum, ent.name, ent.type)
      local info = GlobalState.entity_info_get(unum)
      if info ~= nil then
        clog(" - %s", serpent.line(info))
      end
      auto_player_request.doit(player)
    end
  end)

return M
