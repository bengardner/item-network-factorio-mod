local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Constants = require "src.constants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local GuiManager = require('src.GuiManager')
local clog = require("src.log_console").log

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
This is called when the system opens a diaglog for the tank.
It replaces the dialog with one of our own.
]]
local function network_tank_on_gui_opened(player, entity)
  -- need to start clean each time; there can be only one open at a time
  gui_destroy(player.index)

  local tank_info = GlobalState.get_tank_info(entity.unit_number)
  if tank_info == nil then
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

  local self = my_mgr:create_window(player,  entity.localised_name, {
    window_name = UiConstants.NT_MAIN_FRAME,
    close_button = UiConstants.NT_CLOSE_BTN,
  })
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

  local main_flow = side_flow.add({ type = "flow", direction = "vertical" })

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

  -- NOTE: we could store entity, but then we'd need to check valid before accessing unit_number
  self.unit_number = entity.unit_number
  self.type = default_is_take and "take" or "give"
  self.fluid = default_fluid
  self.buffer = default_buffer
  self.limit = default_limit
  self.temperature = default_temp

  M.update_input_visibility(self)
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
    M.set_limit(self, Constants.MAX_TANK_SIZE)
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
  local buffer = self.buffer
  local limit = self.limit
  local temperature = self.temperature

  if type == "take" then
    if type == nil or fluid == nil or temperature == nil or buffer == nil or limit == nil then
      return nil
    end

    if buffer <= 0 or limit < 0 then
      return nil
    end

    if buffer > Constants.MAX_TANK_SIZE then
      return nil
    end

    return {
      type = type,
      fluid = fluid,
      buffer = buffer,
      limit = limit,
      temperature = temperature,
    }
  else
    if type == nil or limit == nil then
      return nil
    end

    if limit < 0 then
      return nil
    end

    return {
      type = type,
      limit = limit,
    }
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

-------------------------------------------------------------------------------
-- REVISIT: move the fluid search to a separate file?

--[[
Check the fluidbox on the entity. We start with a network tank, so there should only be 1 fluidbox.
Search connected fluidboxes to find all filters.
That gives what the system should contain.
]]
local function search_fluid_system(entity, sysid, visited)
  if entity == nil or not entity.valid then
    return
  end
  local unum = entity.unit_number
  local fluidbox = entity.fluidbox
  -- visited contains [unit_number]=true, ['locked'= { names }, 'min_temp'=X, max_temp=X}]
  visited = visited or { filter={} }
  if unum == nil or fluidbox == nil or visited[unum] ~= nil then
    return
  end
  visited[unum] = true

  -- special case for generators: they allow steam up to 1000 C, but it is a waste, so limit to the real max
  local max_temp
  if entity.type == 'generator' then
    max_temp = entity.prototype.maximum_temperature
  end

  -- scan, locking onto the first fluid_system_id.
  --clog('fluid visiting [%s] name=%s type=%s #fluidbox=%s', unum, entity.name, entity.type, #fluidbox)
  for idx = 1, #fluidbox do
    local fluid = fluidbox[idx]
    local id = fluidbox.get_fluid_system_id(idx)
    if id ~= nil and (sysid == nil or id == sysid) then
      sysid = id
      local conn = fluidbox.get_connections(idx)
      local filt = fluidbox.get_filter(idx)
      local pipes = fluidbox.get_pipe_connections(idx)
      --[[
      clog("   [%s] id=%s capacity=%s fluid=%s filt=%s lock=%s #conn=%s #pipes=%s", idx,
        id,
        fluidbox.get_capacity(idx),
        serpent.line(fluid),
        serpent.line(filt),
        serpent.line(fluidbox.get_locked_fluid(idx)),
        #conn,
        #pipes)
      ]]
      if fluid ~= nil then
        local tt = visited.contents[fluid.name]
        if tt == nil then
          tt = {}
          visited.contents[fluid.name] = tt
        end
        tt[fluid.temperature] = (tt[fluid.temperature] or 0) + fluid.amount
      end

      -- only care about a fluidbox with pipe connections
      if #pipes > 0 then
        -- only update the flow_direction if there is a filter
        if filt ~= nil then
          local f = visited.filter
          local old = f[filt.name]
          if old == nil then
            old = { minimum_temperature=filt.minimum_temperature, maximum_temperature=filt.maximum_temperature }
            f[filt.name] = old
          else
            old.minimum_temperature = math.max(old.minimum_temperature, filt.minimum_temperature)
            old.maximum_temperature = math.min(old.maximum_temperature, filt.maximum_temperature)
          end
          -- correct the max steam temp for generators
          if max_temp ~= nil and max_temp < old.maximum_temperature then
            old.maximum_temperature = max_temp
          end
          for _, pip in ipairs(pipes) do
            visited.flows[pip.flow_direction] = true
          end
        end

        for ci = 1, #conn do
          search_fluid_system(conn[ci].owner, sysid, visited)
        end
      end
    end
  end
end

--[[
Autoconfigure a network tank.
]]
function M.auto_config(self, event)
  -- grab the info and do some sanity checking
  local info = GlobalState.get_tank_info(self.unit_number)
  if info == nil then
    return
  end
  local entity = info.entity
  if not entity.valid then
    return
  end
  local fluidbox = entity.fluidbox
  if fluidbox == nil or #fluidbox ~= 1 then
    return
  end

  --clog("[%s] auto config %s @ %s", self.unit_number, entity.name, serpent.line(entity.position))

  local sysid = fluidbox.get_fluid_system_id(1)
  local visited = { filter={}, flows={}, contents={} }

  search_fluid_system(entity, sysid, visited)
  --clog(" ==> filt=%s  flow=%s cont=%s", serpent.line(visited.filter), serpent.line(visited.flows), serpent.line(visited.contents))

  -- if there are no filters, then we can't auto-config
  if next(visited.filter) == nil then
    clog("network-tank: AUTO: Connect to a fluid provider or consumer")
    return
  end

  -- if there are multitple filters, then we can't auto-config
  if table_size(visited.filter) ~= 1 then
    clog("network-tank: AUTO: Too many fluids: %s", serpent.line(visited.filter))
    return
  end

  -- if there are multiple flow types, then we can't auto-config
  if table_size(visited.flows) ~= 1 then
    clog("network-tank: AUTO: Too many connections.")
    return
  end

  if visited.flows.output == true then
    M.set_mode_give(self)
  else
    -- single input or input-output, find the best fluid temperature
    local name, filt = next(visited.filter)
    self.fluid = name
    self.elems.fluid_picker.elem_value = name
    M.set_mode_take(self)

    -- pick a temperature, stick with the default if none available
    local temps = GlobalState.get_fluids()[name]
    if temps ~= nil then
      local max_temp
      for temp, _ in pairs(temps) do
        if temp >= filt.minimum_temperature and temp <= filt.maximum_temperature then
          if max_temp == nil or temp > max_temp then
            max_temp = temp
          end
        end
      end
      if max_temp ~= nil then
        M.set_temperature(self, max_temp)
      end
    end
  end
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
      if val ~= nil and val ~= false then
        local entity = event.entity
        assert(GlobalState.get_tank_info(entity.unit_number) ~= nil)
        local player = game.get_player(event.player_index)
        if player == nil then
          return
        end
        network_tank_on_gui_opened(player, entity)
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
