local UiConstants = require "src.UiConstants"
local NetworkChestGui = require "src.NetworkChestGui"
local GlobalState = require "src.GlobalState"
local NetworkTankGui = require "src.NetworkTankGui"
local NetworkViewUi = require "src.NetworkViewUi"
local NetworkViewUi_test = require "src.NetworkViewUi_test"
local log = require("src.log_console").log

local M = {}

M.event_handlers = {
  {
    name = UiConstants.ADD_ITEM_BTN_NAME,
    event = "on_gui_click",
    handler = function(event, element)
      local player = game.get_player(event.player_index)
      if player == nil then
        return
      end

      NetworkChestGui.open_modal(player, "add")
    end,
  },
  {
    name = UiConstants.AUTO_ITEM_BTN_NAME,
    event = "on_gui_click",
    handler = function(event, element)
      local player = game.get_player(event.player_index)
      if player == nil then
        return
      end

      NetworkChestGui.Modal.try_to_auto(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_CHOOSE_TAKE_BTN_NAME,
    event = "on_gui_checked_state_changed",
    handler = function(event, element)
      local modal = GlobalState.get_ui_state(event.player_index).network_chest
        .modal
      modal.request_type = "take"
      modal.choose_give_btn.state = false
      if modal.limit ~= nil and modal.limit > 0 then
        NetworkChestGui.Modal.set_default_limit(event.player_index)
      end
      NetworkChestGui.Modal.set_default_buffer_and_limit(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_CHOOSE_GIVE_BTN_NAME,
    event = "on_gui_checked_state_changed",
    handler = function(event, element)
      local modal = GlobalState.get_ui_state(event.player_index).network_chest
        .modal
      modal.request_type = "give"
      modal.choose_take_btn.state = false
      if modal.limit == 0 then
        NetworkChestGui.Modal.set_default_limit(event.player_index)
      end
      NetworkChestGui.Modal.set_default_buffer_and_limit(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_ITEM_PICKER,
    event = "on_gui_elem_changed",
    handler = function(event, element)
      local modal = GlobalState.get_ui_state(event.player_index).network_chest
        .modal
      local item = element.elem_value
      modal.item = item
      NetworkChestGui.Modal.set_default_buffer_and_limit(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_BUFFER_FIELD,
    event = "on_gui_confirmed",
    handler = function(event, element)
      NetworkChestGui.Modal.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_LIMIT_FIELD,
    event = "on_gui_confirmed",
    handler = function(event, element)
      NetworkChestGui.Modal.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_BUFFER_FIELD,
    event = "on_gui_text_changed",
    handler = function(event, element)
      local modal = GlobalState.get_ui_state(event.player_index).network_chest
        .modal
      modal.buffer = tonumber(element.text)
    end,
  },
  {
    name = UiConstants.MODAL_LIMIT_FIELD,
    event = "on_gui_text_changed",
    handler = function(event, element)
      local modal = GlobalState.get_ui_state(event.player_index).network_chest
        .modal
      modal.limit = tonumber(element.text)
    end,
  },
  {
    name = UiConstants.MODAL_CONFIRM_BTN_NAME,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkChestGui.Modal.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.MODAL_CANCEL_BTN_NAME,
    event = "on_gui_click",
    handler = function(event, element)
      local player = game.get_player(event.player_index)
      NetworkChestGui.close_modal(player)
    end,
  },
  {
    name = UiConstants.CANCEL_NETWORK_CHEST_BTN_NAME,
    event = "on_gui_click",
    handler = function(event, element)
      local player = game.get_player(event.player_index)
      NetworkChestGui.close_main_frame(player, false)
    end,
  },
  {
    name = UiConstants.SAVE_NETWORK_CHEST_BTN_NAME,
    event = "on_gui_click",
    handler = function(event, element)
      local player = game.get_player(event.player_index)
      NetworkChestGui.close_main_frame(player, true)
    end,
  },
  {
    name = UiConstants.REMOVE_REQUEST_BTN,
    event = "on_gui_click",
    handler =  NetworkChestGui.remove_request_line,
  },
  {
    name = UiConstants.UPDATE_REQEUST_BTN,
    event = "on_gui_click",
    handler =  NetworkChestGui.on_chest_request_update,
  },
  {
    name = UiConstants.EDIT_REQUEST_BTN,
    event = "on_gui_click",
    handler = function(event, element)
      local request_id = element.tags.request_id
      assert(request_id ~= nil)

      local player = game.get_player(event.player_index)
      NetworkChestGui.open_modal(player, "edit", request_id)
    end,
  },
  {
    name = UiConstants.NT_CHOOSE_TAKE_BTN,
    event = "on_gui_click",
    handler = function(event, element)
      local nt_ui = GlobalState.get_ui_state(event.player_index).network_tank
      nt_ui.type = "take"
      nt_ui.choose_give_btn.state = false
      NetworkTankGui.set_default_buffer_and_limit(event.player_index)
      NetworkTankGui.update_input_visibility(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_CHOOSE_GIVE_BTN,
    event = "on_gui_click",
    handler = function(event, element)
      local nt_ui = GlobalState.get_ui_state(event.player_index).network_tank
      nt_ui.type = "give"
      nt_ui.choose_take_btn.state = false
      NetworkTankGui.set_default_buffer_and_limit(event.player_index)
      NetworkTankGui.update_input_visibility(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_FLUID_PICKER,
    event = "on_gui_elem_changed",
    handler = function(event, element)
      local nt_ui = GlobalState.get_ui_state(event.player_index).network_tank
      local fluid = element.elem_value
      nt_ui.fluid = fluid
      NetworkTankGui.set_default_buffer_and_limit(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_TEMP_FIELD,
    event = "on_gui_confirmed",
    handler = function(event, element)
      NetworkTankGui.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_BUFFER_FIELD,
    event = "on_gui_confirmed",
    handler = function(event, element)
      NetworkTankGui.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_LIMIT_FIELD,
    event = "on_gui_confirmed",
    handler = function(event, element)
      NetworkTankGui.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_TEMP_FIELD,
    event = "on_gui_text_changed",
    handler = function(event, element)
      local nt_ui = GlobalState.get_ui_state(event.player_index).network_tank
      nt_ui.temperature = tonumber(element.text)
    end,
  },
  {
    name = UiConstants.NT_BUFFER_FIELD,
    event = "on_gui_text_changed",
    handler = function(event, element)
      local nt_ui = GlobalState.get_ui_state(event.player_index).network_tank
      nt_ui.buffer = tonumber(element.text)
    end,
  },
  {
    name = UiConstants.NT_LIMIT_FIELD,
    event = "on_gui_text_changed",
    handler = function(event, element)
      local nt_ui = GlobalState.get_ui_state(event.player_index).network_tank
      nt_ui.limit = tonumber(element.text)
    end,
  },
  {
    name = UiConstants.NT_CONFIRM_EVENT,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkTankGui.try_to_confirm(event.player_index)
    end,
  },
  {
    name = UiConstants.NT_CANCEL_EVENT,
    event = "on_gui_click",
    handler = function(event, element)
      local player = game.get_player(event.player_index)
      local ui = GlobalState.get_ui_state(event.player_index)
      NetworkTankGui.reset(player, ui)
    end,
  },
  {
    name = UiConstants.NV_REFRESH_BTN,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.update_items(event.player_index)
    end,
  },
  {
    name = UiConstants.NV_DEPOSIT_ITEM_SPRITE_BUTTON,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.on_gui_click_item(event, element)
    end,
  },
  {
    name = UiConstants.NV_ITEM_SPRITE_BUTTON,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.on_gui_click_item(event, element)
    end,
  },
  {
    name = UiConstants.NV_TABBED_PANE,
    event = "on_gui_selected_tab_changed",
    handler = function(event, element)
      NetworkViewUi.update_items(event.player_index)
    end,
  },
  {
    name = UiConstants.NV_ITEM_SPRITE,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.on_gui_click_item(event, element)
    end
  },
  {
    name = UiConstants.NV_LIMIT_ITEM,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.on_limit_click_item(event, element)
    end
  },
  {
    name = UiConstants.NV_LIMIT_SELECT_ITEM,
    event = "on_gui_elem_changed",
    handler = function(event, element)
      NetworkViewUi.on_limit_item_elem_changed(event, element)
    end
  },
  {
    name = UiConstants.NV_LIMIT_SELECT_FLUID,
    event = "on_gui_elem_changed",
    handler = function(event, element)
      NetworkViewUi.on_limit_fluid_elem_changed(event, element)
    end
  },
  {
    name = UiConstants.NV_LIMIT_TYPE,
    event = "on_gui_selection_state_changed",
    handler = function(event, element)
      NetworkViewUi.on_limit_elem_type(event, element)
    end
  },
  {
    name = UiConstants.NV_LIMIT_SAVE,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.on_limit_save(event, element)
    end
  },
  {
    name = UiConstants.NV_PIN_BTN,
    event = "on_gui_click",
    handler = function(event, element)
      NetworkViewUi.on_gui_pin(event)
    end,
  },
}

M.handler_map = {}
for _, handler in ipairs(M.event_handlers) do
  local name_map = M.handler_map[handler.event]
  if name_map == nil then
    M.handler_map[handler.event] = {}
    name_map = M.handler_map[handler.event]
  end
  assert(name_map[handler.name] == nil)
  name_map[handler.name] = handler
end

function M.handle_generic_gui_event(event, event_type)
  local element = event.element
  if element == nil then
    return
  end
  local name = element.tags.event
  if name == nil then
    return
  end
  local name_map = M.handler_map[event_type]
  if name_map == nil then
    return
  end
  local handler = name_map[name]
  if handler == nil then
    return
  end
  handler.handler(event, element)
end

return M
