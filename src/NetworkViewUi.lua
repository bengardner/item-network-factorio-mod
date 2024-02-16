local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local UiNetworkItems = require "src.UiNetworkItems"
local UiNetworkFluid = require "src.UiNetworkFluid"
local UiNetworkLimits = require "src.UiNetworkLimits"
local UiNetworkShortages = require "src.UiNetworkShortages"
local UiNetworkFuels = require "src.UiNetworkFuels"
local clog = require("src.log_console").log

local M = {}

M.WIDTH = 490
M.HEIGHT = 500

local function gui_get(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  return ui.net_view, ui
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).net_view = value
end

-------------------------------------------------------------------------------
-- Create the main GUI frame / window
-------------------------------------------------------------------------------
function M.open_main_frame(player_index)
  -- if we already have a GUI, then destroy it
  local self = gui_get(player_index)
  if self ~= nil then
    M.destroy(self)
    return
  end

  -- make sure the player is valid
  local player = game.get_player(player_index)
  if player == nil then
    return
  end

  --local width = M.WIDTH
  local height = M.HEIGHT + 22

  --[[
  I want the GUI to look like this:

  +--------------------------------------------------+
  | Network View ||||||||||||||||||||||||||||| [R][X]|
  +--------------------------------------------------+
  | Items | Fluids | Shortages | Limits |            | <- tabs
  +--------------------------------------------------+
  | [I]  [I]  [I]  [I]  [I]  [I]  [I]  [I]  [I]  [I] | <- tab content
    ... repeated ...
  | [I]  [I]  [I]  [I]  [I]  [I]  [I]  [I]  [I]  [I] |
  +--------------------------------------------------+

  [R] is refresh button and [X] is close. [I] are item icons with the number overlay.
  The ||||| stuff makes the window draggable.
  ]]

  -- create the main window
  local frame = player.gui.screen.add({
    type = "frame",
    name = UiConstants.NV_FRAME,
  })
  player.opened = frame
  --frame.style.size = { width, height }
  frame.style.height = height
  frame.auto_center = true

  -- table that holds all info for this GUI
  self = {
    player = player,
    frame = frame,
    elems = { network_view = frame },
    children = {},
    pinned = false
  }
  local elems = self.elems

  -- need a vertical flow to wrap (header, body)
  local main_flow = frame.add({
    type = "flow",
    direction = "vertical",
  })
  main_flow.style.height = M.HEIGHT

  -- create the flow for the header/title bar
  local header_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  header_flow.drag_target = frame
  header_flow.style.height = 24

  header_flow.add {
    type = "label",
    caption = "Network View",
    style = "frame_title",
    ignored_by_interaction = true,
  }

  local header_drag = header_flow.add {
    type = "empty-widget",
    style = "draggable_space",
    ignored_by_interaction = true,
  }
  --header_drag.style.size = { M.WIDTH - 210, 20 }
  header_drag.style.height = 20
  header_drag.style.horizontally_stretchable = true
  --header_drag.style.vertically_stretchable = true

  local search_enabled = false
  if search_enabled then
    header_flow.add{
      type = "textfield",
      style = "titlebar_search_textfield",
    }

    header_flow.add{
      name = UiConstants.NV_SEARCH_BTN,
      type = "sprite-button",
      sprite = 'utility/search_white',
      hovered_sprite = 'utility/search_black',
      clicked_sprite = 'utility/search_black',
      style = "frame_action_button",
      tooltip = { "gui.search" },
    }
  end

  header_flow.add {
    name = UiConstants.NV_REFRESH_BTN,
    type = "sprite-button",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = { "gui.refresh" },
  }

  elems.close_button = header_flow.add {
    name = UiConstants.NV_CLOSE_BTN,
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
  }

  elems.pin_button = header_flow.add {
    name = UiConstants.NV_PIN_BTN,
    type = "sprite-button",
    sprite = "flib_pin_white",
    hovered_sprite = "flib_pin_black",
    clicked_sprite = "flib_pin_black",
    style = "frame_action_button",
  }

  -- add the tabbed frame
  local tabbed_pane = main_flow.add {
    name = UiConstants.NV_TABBED_PANE,
    type = "tabbed-pane",
  }
  elems.tabbed_pane = tabbed_pane

  local function add_tab(caption, ui_class)
    local the_tab = tabbed_pane.add { type = "tab", caption = caption }
    local the_inst = ui_class.create(tabbed_pane, player)
    table.insert(self.children, the_inst)
    tabbed_pane.add_tab(the_tab, the_inst.frame)
  end

  add_tab("Items", UiNetworkItems)
  add_tab("Fluids", UiNetworkFluid)
  add_tab("Shortages", UiNetworkShortages)
  add_tab("Limits", UiNetworkLimits)
  add_tab("Fuels", UiNetworkFuels)

  -- select "items" (not really needed, as that is the default)
  tabbed_pane.selected_tab_index = 1

  -- save the GUI data for this player
  gui_set(player_index, self)

  -- refresh the page
  M.update_items(player_index)
end

function M.update_items(player_index)
  local self = gui_get(player_index)
  if self ~= nil then
    self.children[self.elems.tabbed_pane.selected_tab_index]:refresh()
  end
end

--------------------------------------------------------------------------------

function M.destroy(self)
  if self ~= nil then
    for _, ch in pairs(self.children) do
      if type(ch.destroy) == "function" then
        ch.destroy(ch)
      end
    end
    self.frame.destroy()
    gui_set(self.player.index, nil)
  end
end

function M.on_gui_closed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    if self.pinned then
      return
    end
    M.destroy(self)
  end
end

-- close button pressed
function M.on_click_close_button(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    M.destroy(self)
  end
end

function M.on_every_5_seconds(event)
  for player_index, _ in pairs(GlobalState.get_player_info_map()) do
    M.update_items(player_index)
  end
end

-- grab and verify the player
local function limit_event_prep(event)
  local player = game.get_player(event.player_index)
  if player == nil then
    return
  end
  local self = gui_get(event.player_index)
  if self == nil then
    return
  end
  if self.view_type ~= "limits" then
    return
  end
  local tabbed_pane = self.elems.tabbed_pane
  local main_flow = tabbed_pane.tabs[tabbed_pane.selected_tab_index].content
  if main_flow == nil then
    return
  end
  return player,  main_flow.edit_flow
end

-- type_idx: 1=item 2=fluid
local function limit_set_edit_type(edit_flow, type_idx)
  edit_flow.fluid_edit.visible = (type_idx == 2)
  edit_flow.item_edit.visible = (type_idx ~= 2)
  edit_flow[UiConstants.NV_LIMIT_TYPE].selected_index = type_idx
end

local function limit_set_edit_item(edit_flow, item_name, item_temp)
  if item_name ~= nil then

    local prot = game.item_prototypes[item_name]
    if prot ~= nil then
      local item_limit = GlobalState.get_limit(item_name)
      --clog("limit_set_edit_item: item [%s] group [%s] subgroup [%s] limit=%s",
      --  item_name, prot.group.name, prot.subgroup.name, item_limit)
      limit_set_edit_type(edit_flow, 1)
      edit_flow.item_edit[UiConstants.NV_LIMIT_SELECT_ITEM].elem_value = item_name
      edit_flow.new_limit.text = string.format("%s", item_limit)
      edit_flow.new_limit.select(1, 0)
    else
      local fprot = game.fluid_prototypes[item_name]
      if fprot ~= nil then
        if item_temp == nil then
          item_temp = fprot.default_temperature
        end
        local key = GlobalState.fluid_temp_key_encode(item_name, item_temp)
        local item_limit = GlobalState.get_limit(key)
        --clog("limit_set_edit_item: fluid [%s] limit=%s", key , item_limit)
        limit_set_edit_type(edit_flow, 2)
        edit_flow.fluid_edit[UiConstants.NV_LIMIT_SELECT_FLUID].elem_value = item_name
        edit_flow.fluid_edit.temperature.text = string.format("%s", item_temp)
        edit_flow.fluid_edit.temperature.select(1, 0)
        edit_flow.new_limit.text = string.format("%s", item_limit)
        edit_flow.new_limit.select(1, 0)
      end
    end
  end
end

-- the selection change. refresh the current limit text box
function M.on_limit_item_elem_changed(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil or edit_flow == nil then
    return
  end

  limit_set_edit_item(edit_flow, edit_flow.item_edit[UiConstants.NV_LIMIT_SELECT_ITEM].elem_value)
end

-- the selection change. refresh the current limit text box
function M.on_limit_fluid_elem_changed(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil or edit_flow == nil then
    return
  end

  limit_set_edit_item(edit_flow, edit_flow.fluid_edit[UiConstants.NV_LIMIT_SELECT_FLUID].elem_value)
end

-- read the limit and save to the limits structure
function M.on_limit_save(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil or edit_flow == nil then
    return
  end

  if edit_flow.item_edit.visible then
    -- item
    local item_name = edit_flow.item_edit[UiConstants.NV_LIMIT_SELECT_ITEM].elem_value
    if item_name ~= nil then
      clog("setting item %s limit %s", item_name, edit_flow.new_limit.text)
      if GlobalState.set_limit(item_name, edit_flow.new_limit.text) then
        M.update_items(player.index)
      end
    end
  else
    -- fluid
    local fluid_name = edit_flow.fluid_edit[UiConstants.NV_LIMIT_SELECT_FLUID].elem_value
    local fluid_temp = tonumber(edit_flow.fluid_edit.temperature.text)
    if fluid_name ~= nil and fluid_temp ~= nil then
      local key = GlobalState.fluid_temp_key_encode(fluid_name, fluid_temp)
      clog("setting fluid %s limit %s", key, edit_flow.new_limit.text)
      if GlobalState.set_limit(key, edit_flow.new_limit.text) then
        M.update_items(player.index)
      end
    end
  end
end

function M.on_limit_click_item(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil then
    return
  end

  local item_name = event.element.tags.item
  local item_temp = event.element.tags.temp
  if item_name ~= nil then
    -- transfer the existing info to the edit box
    limit_set_edit_item(edit_flow, item_name, item_temp)

    if event.button == defines.mouse_button_type.right then
      if game.item_prototypes[item_name] ~= nil then
        GlobalState.clear_limit(item_name)
      elseif item_temp ~= nil and game.fluid_prototypes[item_name] ~= nil then
        local key = GlobalState.fluid_temp_key_encode(item_name, item_temp)
        GlobalState.clear_limit(key)
      end
      M.update_items(player.index)
    end
  end
end

function M.on_limit_elem_type(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil or edit_flow == nil then
    return
  end

  limit_set_edit_type(edit_flow, edit_flow.elem_type_dropdown.selected_index)
end

function M.toggle_pinned(self)
  -- "Pinning" the GUI will remove it from player.opened, allowing it to coexist with other windows.
  -- I highly recommend implementing this for your GUIs. flib includes the requisite sprites and locale for the button.
  self.pinned = not self.pinned
  if self.pinned then
    self.elems.close_button.tooltip = { "gui.close" }
    self.elems.pin_button.sprite = "flib_pin_black"
    self.elems.pin_button.style = "flib_selected_frame_action_button"
    if self.player.opened == self.elems.network_view then
      self.player.opened = nil
    end
  else
    self.elems.close_button.tooltip = { "gui.close-instruction" }
    self.elems.pin_button.sprite = "flib_pin_white"
    self.elems.pin_button.style = "frame_action_button"
    self.player.opened = self.elems.network_view
  end
end

function M.on_gui_pin(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    M.toggle_pinned(self)
  end
end

function M.on_click_refresh_button(event)
  M.update_items(event.player_index)
end

-- header buttons
Gui.on_click(UiConstants.NV_PIN_BTN, M.on_gui_pin)
Gui.on_click(UiConstants.NV_CLOSE_BTN, M.on_click_close_button)
Gui.on_click(UiConstants.NV_REFRESH_BTN, M.on_click_refresh_button)

-- tabbed thingy
Event.register(
  defines.events.on_gui_selected_tab_changed,
  function(event, element)
    M.update_items(event.player_index)
  end,
  Event.Filters.gui,
  UiConstants.NV_TABBED_PANE
)

-- item page (moved to UiNetworkItems -- can remove
--Gui.on_click(UiConstants.NV_DEPOSIT_ITEM_SPRITE_BUTTON, M.on_gui_click_item)
--Gui.on_click(UiConstants.NV_ITEM_SPRITE_BUTTON, M.on_gui_click_item)

--[[
-- limit page (need to move to UiNetworkLimits)
Gui.on_click(UiConstants.NV_LIMIT_ITEM, M.on_limit_click_item)
Gui.on_selection_state_changed(UiConstants.NV_LIMIT_TYPE, M.on_limit_elem_type)
Gui.on_elem_changed(UiConstants.NV_LIMIT_SELECT_ITEM, M.on_limit_item_elem_changed)
Gui.on_elem_changed(UiConstants.NV_LIMIT_SELECT_FLUID, M.on_limit_fluid_elem_changed)
Gui.on_click(UiConstants.NV_LIMIT_SAVE, M.on_limit_save)
]]

-- item_utils.filter_name_or_tag

-- Gui doesn't have on_gui_closed, so add it manually
Event.register(defines.events.on_gui_closed, M.on_gui_closed, Event.Filters.gui, UiConstants.NV_FRAME)

-- hotkey handler
Event.on_event("in_open_network_view", function (event)
    M.open_main_frame(event.player_index)
  end)

return M
