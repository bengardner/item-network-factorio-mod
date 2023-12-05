local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Constants = require "src.constants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local GuiManager = require('src.GuiManager')
local clog = require("src.log_console").log
local NetworkTankAutoConfig = require("src.NetworkTankAutoConfig")

-- this is the fake metatable - all functions take an instance created via
-- network_tank_on_gui_opened() as the first parameter.
local M = {}

local my_mgr = GuiManager.new("network_tank")

--  Destroy the GUI for a player
-- this can be a generic function
local function gui_destroy(player_index)
  my_mgr:destroy(player_index)
end

--[[
  Destroys the old gui and retrieves the info for the tank.
  If found, creates the new window with the preview and save/cancel buttons on the bottom.
  returns the class instance, main_flow and tank_info
]]
local function common_on_gui_opened(player, entity)
  -- need to start clean each time; there can be only one open at a time
  gui_destroy(player.index)

  local tank_info = GlobalState.get_tank_info(entity.unit_number)
  if tank_info == nil then
    return nil
  end

  local self = my_mgr:create_window(player, entity.localised_name, {
    window_name = UiConstants.NT_MAIN_FRAME,
    close_button = UiConstants.NT_CLOSE_BTN,
  })
  self.unit_number = entity.unit_number

  local elems = self.elems

  local frame = elems.body

  local frame_flow = frame.add({ type = "flow", direction = "horizontal" })
  local inner_frame = frame_flow.add({ type = "frame", style = "inside_shallow_frame_with_padding" })

  local side_flow = inner_frame.add({ type = "flow", direction = "horizontal" })

  local preview_frame = side_flow.add({
    type = "frame",
    style = "deep_frame_in_shallow_frame",
  })
  local entity_preview = preview_frame.add({
    type = "entity-preview",
    style = "wide_entity_button",
  })
  entity_preview.style.horizontally_stretchable = false
  entity_preview.style.minimal_width = 100
  entity_preview.style.natural_height = 100
  entity_preview.style.height = 100
  entity_preview.entity = entity

  local right_flow = side_flow.add({ type = "flow", direction = "vertical" })
  local main_flow = right_flow.add({ type = "flow", direction = "vertical" })

  local save_cancel_flow = right_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  save_cancel_flow.add({
    name = UiConstants.NT_CONFIRM_EVENT,
    type = "button",
    caption = "Save",
  })
  save_cancel_flow.add({
    name = UiConstants.NT_CANCEL_EVENT,
    type = "button",
    caption = "Cancel",
  })

  return self, main_flow, tank_info
end

--[[
This is called when the system opens a diaglog for the tank.
It replaces the dialog with one of our own.

@is_requester true=requester, other=net-tank
]]
local function network_tank_on_gui_opened(player, entity, is_requester)

  local self, main_flow, tank_info = common_on_gui_opened(player, entity)
  if self == nil then
    return
  end

  local default_is_take = true
  local default_fluid = nil
  local default_buffer = nil
  local default_limit = nil
  local default_temp = nil

  if tank_info.config ~= nil then
    default_is_take = tank_info.config.type == "take"
    default_fluid = tank_info.config.fluid
    default_buffer = tank_info.config.buffer
    default_limit = tank_info.config.limit
    default_temp = tank_info.config.temperature
  end

  if is_requester == true then
    default_is_take = true
  end

  local elems = self.elems

  local frame = elems.body

  local auto_flow = main_flow.add({ type = "flow", direction = "horizontal" })
  auto_flow.add({
    name = UiConstants.NT_BTN_AUTO,
    type = "button",
    caption = "AUTO",
  })
  auto_flow.style.horizontally_stretchable = true
  auto_flow.style.horizontal_align = "center"
  auto_flow.style.vertical_align = "center"

  elems.type_flow = main_flow.add({ type = "flow", direction = "horizontal" })
  elems.type_flow.add({ type = "label", caption = "Type:" })
  elems.choose_take_btn = elems.type_flow.add({
    name = UiConstants.NT_CHOOSE_TAKE_BTN,
    type = "radiobutton",
    state = default_is_take,
  })
  elems.type_flow.add({ type = "label", caption = "Request" })
  if is_requester == true then
    elems.type_flow.visible = false
  end

  elems.choose_give_btn = elems.type_flow.add({
    name = UiConstants.NT_CHOOSE_GIVE_BTN,
    type = "radiobutton",
    state = not default_is_take,
  })
  elems.type_flow.add({ type = "label", caption = "Provide" })

  elems.request_flow = main_flow.add({ type = "flow", direction = "vertical" })

  elems.fluid_flow = elems.request_flow.add({ type = "flow", direction = "horizontal" })
  elems.fluid_flow.add({ type = "label", caption = "Fluid:" })
  elems.fluid_picker = elems.fluid_flow.add({
    name = UiConstants.NT_FLUID_PICKER,
    type = "choose-elem-button",
    elem_type = "fluid",
    elem_value = default_fluid,
  })
  elems.fluid_picker.elem_value = default_fluid

  elems.temp_flow = elems.request_flow.add({ type = "flow", direction = "horizontal" })
  elems.temp_flow.add({ type = "label", caption = "Temperature:" })
  elems.temperature_input = elems.temp_flow.add({
    name = UiConstants.NT_TEMP_FIELD,
    type = "textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = true,
  })
  if default_temp ~= nil then
    elems.temperature_input.text = string.format("%s", default_temp)
  end
  elems.temperature_input.style.width = 100

  elems.buffer_flow = elems.request_flow.add({ type = "flow", direction = "horizontal" })
  elems.buffer_flow.add({ type = "label", caption = "Buffer:" })
  elems.buffer_size_input = elems.buffer_flow.add({
    name = UiConstants.NT_BUFFER_FIELD,
    type = "textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
  })
  if default_buffer ~= nil then
    elems.buffer_size_input.text = string.format("%s", default_buffer)
  end
  elems.buffer_size_input.style.width = 100

  -- this is always shown
  local limit_flow = main_flow.add({ type = "flow", direction = "horizontal" })
  limit_flow.add({ type = "label", caption = "Limit:" })
  elems.limit_input = limit_flow.add({
    name = UiConstants.NT_LIMIT_FIELD,
    type = "textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
  })
  if default_limit ~= nil then
    elems.limit_input.text = string.format("%s", default_limit)
  end
  elems.limit_input.style.width = 100

  --[[
  add_save_cancel(main_flow)
  local save_cancel_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  save_cancel_flow.add({
    name = UiConstants.NT_CONFIRM_EVENT,
    type = "button",
    caption = "Save",
  })
  save_cancel_flow.add({
    name = UiConstants.NT_CANCEL_EVENT,
    type = "button",
    caption = "Cancel",
  })
]]
  self.type = default_is_take and "take" or "give"
  self.fluid = default_fluid
  self.buffer = default_buffer
  self.limit = default_limit
  self.temperature = default_temp

  M.update_input_visibility(self)
end

--[[

]]
local function network_tank_provider_on_gui_opened(player, entity)
  local self, main_flow, tank_info = common_on_gui_opened(player, entity)
  if self == nil then
    return
  end

  local default_buffer = nil

  if tank_info.config ~= nil then
    default_buffer = tank_info.config.buffer
  end

  self.type = "give"
  self.buffer = default_buffer

  M.update_buffer_slider(self)
end

function M.reset(self)
  gui_destroy(self.player.index)
end

function M.update_input_visibility(self)
  local visible = self.type == "take"
  self.elems.request_flow.visible = visible
  --self.elems.fluid_flow.visible = visible
  --self.elems.temp_flow.visible = visible
  --self.elems.buffer_flow.visible = visible
end

function M.set_default_buffer_and_limit(self)
  local fluid = self.fluid
  local type = self.type
  if type == "give" then
    M.set_limit(self, 0)
  elseif fluid ~= nil and type ~= nil then
    local limit
    if type == "take" then
      limit = 0
    else
      limit = Constants.MAX_TANK_SIZE
    end
    M.set_temperature(self, game.fluid_prototypes[fluid].default_temperature)
    M.set_buffer(self, Constants.MAX_TANK_SIZE)
    M.set_limit(self, limit)
  end
end

function M.set_temperature(self, temperature)
  self.temperature = temperature
  self.elems.temperature_input.text = string.format("%d", temperature)
end

function M.set_buffer(self, buffer)
  self.buffer = buffer
  self.elems.buffer_size_input.text = string.format("%d", buffer)
end

function M.set_limit(self, limit)
  self.limit = limit
  self.elems.limit_input.text = string.format("%d", limit)
end

function M.get_config_from_network_tank_ui(self)
  local type = self.type
  local fluid = self.fluid
  local buffer = self.buffer or 0
  local limit = self.limit or 0
  local temperature = self.temperature or 0

  buffer = math.max(0, math.min(buffer, Constants.MAX_TANK_SIZE))
  limit = math.max(0, limit)

  if type == "take" then

    local config = {
      type = type,
      fluid = fluid,
      buffer = buffer,
      limit = limit,
      temperature = temperature,
    }
    if limit == 0 then
      config.no_limit = true
    end
    return config

  else
    -- "give" meaning sending to the network
    local config = {
      type = "give",
      limit = limit,
    }
    if limit == 0 then
      config.no_limit = true
    end
    return config
  end
end

function M.try_to_confirm(self)
  local config = M.get_config_from_network_tank_ui(self)
  if config == nil then
    return
  end

  -- may have been removed since the dialog was opened
  local info = GlobalState.get_tank_info(self.unit_number)
  if info == nil then
    return
  end

  info.config = config

  M.reset(self)
end

--[[
Autoconfigure a network tank.
]]
function M.auto_config(self, event)
  local info = GlobalState.get_tank_info(self.unit_number)
  if info == nil then
    return
  end

  local config = NetworkTankAutoConfig.auto_config(info.entity)
  if config == nil then
    return
  end

  if config.type == "give" then
    M.set_mode_give(self)
    return
  end

  self.fluid = config.fluid
  self.elems.fluid_picker.elem_value = config.fluid
  M.set_mode_take(self)
  M.set_temperature(self, config.temperature)
end

function M.set_mode_give(self)
  self.type = "give"
  self.elems.choose_take_btn.state = false
  M.set_default_buffer_and_limit(self)
  M.update_input_visibility(self)
end

function M.set_mode_take(self)
  self.type = "take"
  self.elems.choose_give_btn.state = false
  M.set_default_buffer_and_limit(self)
  M.update_input_visibility(self)
end

-------------------------------------------------------------------------------
-- GUI: event functions

Gui.on_click(UiConstants.NT_CHOOSE_TAKE_BTN, my_mgr:wrap(function (self, event)
  M.set_mode_take(self)
end))

Gui.on_click(UiConstants.NT_CHOOSE_GIVE_BTN, my_mgr:wrap(function (self, event)
  M.set_mode_give(self)
end))

Gui.on_elem_changed(UiConstants.NT_FLUID_PICKER, my_mgr:wrap(function (self, event)
  local fluid = event.element.elem_value
  self.fluid = fluid
  M.set_default_buffer_and_limit(self)
end))

Gui.on_confirmed(UiConstants.NT_TEMP_FIELD, my_mgr:wrap(function (self, event)
  M.try_to_confirm(self)
end))

Gui.on_confirmed(UiConstants.NT_BUFFER_FIELD, my_mgr:wrap(function (self, event)
  M.try_to_confirm(self)
end))

Gui.on_confirmed(UiConstants.NT_LIMIT_FIELD, my_mgr:wrap(function (self, event)
  M.try_to_confirm(self)
end))

Gui.on_text_changed(UiConstants.NT_TEMP_FIELD, my_mgr:wrap(function (self, event)
  self.temperature = tonumber(event.element.text)
end))

Gui.on_text_changed(UiConstants.NT_BUFFER_FIELD, my_mgr:wrap(function (self, event)
  self.buffer = tonumber(event.element.text)
end))

Gui.on_text_changed(UiConstants.NT_LIMIT_FIELD, my_mgr:wrap(function (self, event)
  self.limit = tonumber(event.element.text)
end))

Gui.on_click(UiConstants.NT_CONFIRM_EVENT, my_mgr:wrap(function (self, event)
  M.try_to_confirm(self)
end))

Gui.on_click(UiConstants.NT_CANCEL_EVENT, my_mgr:wrap(function (self, event)
  gui_destroy(event.player_index)
end))

Gui.on_click(UiConstants.NT_CLOSE_BTN, my_mgr:wrap(function (self, event)
  M.try_to_confirm(self)
end))

Gui.on_click(UiConstants.NT_BTN_AUTO, my_mgr:wrap(function (self, event)
  M.auto_config(self, event)
end))

-------------------------------------------------------------------------------

-- when the player left-clicks on an entity, the default dialog is created and then
-- this is called. This replaces the default dialog.
Event.on_event(
  defines.events.on_gui_opened,
  function (event)
    if event.gui_type == defines.gui_type.entity then
      local val = Constants.NETWORK_TANK_NAMES[event.entity.name]
      if val ~= nil then
        local entity = event.entity
        assert(GlobalState.get_tank_info(entity.unit_number) ~= nil)
        local player = game.get_player(event.player_index)
        if player == nil then
          return
        end
        if val == false then
          -- network_tank_provider_on_gui_opened(player, entity, val)
        else
          network_tank_on_gui_opened(player, entity, val)
        end
      end
    end
  end
)

Event.on_event(
  defines.events.on_gui_closed,
  my_mgr:wrap(function (self, event)
    local frame = event.element
    if frame ~= nil and frame.name == UiConstants.NT_MAIN_FRAME then
      M.reset(self)
    end
  end)
)

-- dummy return -- nothing is exported anymore
return {}
