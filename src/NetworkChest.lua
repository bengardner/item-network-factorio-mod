local GlobalState = require "src.GlobalState"
local NetworkChestGui = require "src.NetworkChestGui"
local UiHandlers = require "src.UiHandlers"
local NetworkViewUi = require "src.NetworkViewUi"
local UiConstants = require "src.UiConstants"
local Event = require('__stdlib__/stdlib/event/event')
local util = require("util") -- from core/lualib
local constants = require("constants")
local clog = require("src.log_console").log

local M = {}

--function M.on_init()
  --GlobalState.setup()
--end


local function generic_create_handler(event)
  --clog("generic create %s", serpent.line(event))
  local entity = event.created_entity or event.entity or event.destination
  if entity == nil then
    return
  end
  local service_type = GlobalState.get_service_type_for_entity(entity.name)
  if service_type == nil then
    clog("created unhandled %s [%s] %s", entity.name, entity.type, entity.unit_number)
    return
  end

  local svc_func = GlobalState.get_service_task(service_type)
  if svc_func == nil then
    clog("ERROR: no def for %s", service_type)
    return
  end

  clog("generic_create_handler [%s] => %s", entity.name, serpent.line(svc_func))
  if type(svc_func.create) == "function" then
    svc_func.create(entity, event.tags)
  else
    clog("ERROR: no create for %s", entity.name)
  end
end

function M.on_built_entity(event)
  generic_create_handler(event)
end

function M.script_raised_built(event)
  generic_create_handler(event)
end

function M.on_entity_cloned(event)
  -- only handle same-name clones
  if event.source.name ~= event.destination.name then
    return
  end
  local name = event.source.name

  -- grab the service_type for the entity name
  local svc_type = GlobalState.get_service_type_for_entity(name)
  if svc_type == nil then
    -- entity not handled
    return
  end
  -- grab the functions for the service_type
  local svc_func = GlobalState.get_service_task(svc_type)
  if svc_func == nil then
    -- how did we get called?
    error(string.format("No functions for service_type %s", svc_type))
    return
  end

  -- create the dest, if needed
  svc_func.create(event.destination)

  -- see if there is a clone method for this type
  if type(svc_func.clone) ~= "function" then
    return
  end

  -- make sure both instances exist
  local dst_info = GlobalState.entity_info_get(event.destination.unit_number)
  local src_info = GlobalState.entity_info_get(event.source.unit_number)
  if dst_info ~= nil and src_info ~= nil then
    svc_func.clone(dst_info, src_info)
  end
end

function M.on_robot_built_entity(event)
  generic_create_handler(event)
end

function M.script_raised_revive(event)
  generic_create_handler(event)
end

function M.generic_destroy_handler(event, opts)
  if opts == nil then
    opts = {}
  end

  local entity = event.entity
  local unit_number = entity.unit_number
  if unit_number == nil then
    return
  end

  local info = GlobalState.entity_info_get(unit_number)
  if info == nil then
    return
  end

  -- put any fluids or items in the network
  GlobalState.put_contents_in_network(entity)

  if not opts.do_not_delete_entity then
    GlobalState.entity_info_clear(unit_number)
  end

  -- TODO: close the network chest main GUI
  -- close the network chest GUI pop-up
  if global.mod.network_chest_gui ~= nil and
      global.mod.network_chest_gui.entity.unit_number == unit_number
  then
    global.mod.network_chest_gui.frame.destroy()
    global.mod.network_chest_gui = nil
  end

  -- TODO: close the network tank GUI
end

function M.on_player_mined_entity(event)
  M.generic_destroy_handler(event)
end

function M.on_pre_player_mined_item(event)
  M.generic_destroy_handler(event)
end

function M.on_robot_mined_entity(event)
  M.generic_destroy_handler(event)
end

function M.script_raised_destroy(event)
  M.generic_destroy_handler(event)
end

function M.on_entity_died(event)
  M.generic_destroy_handler(event, { do_not_delete_entity = true })
end

function M.on_marked_for_deconstruction(event)
  -- put any fluids or items in the network
  GlobalState.put_contents_in_network(event.entity)
end

function M.on_post_entity_died(event)
  if event.unit_number ~= nil then
    local info = GlobalState.entity_info_get(event.unit_number)
    if info ~= nil then
      if event.ghost ~= nil then
        if info.requests ~= nil then
          -- network-chest
          event.ghost.tags = { requests = info.requests }
        elseif info.config ~= nil then
          -- network-tank
          event.ghost.tags = { config = info.config }
        end
      end

      GlobalState.entity_info_clear(event.unit_number)
    end
  end
end

-- copied from https://discord.com/channels/139677590393716737/306402592265732098/1112775784411705384
-- on the factorio discord
-- thanks raiguard :)
local function get_blueprint(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  local bp = player.blueprint_to_setup
  if bp and bp.valid_for_read then
    return bp
  end

  bp = player.cursor_stack
  if not bp or not bp.valid_for_read then
    return nil
  end

  if bp.type == "blueprint-book" then
    local item_inventory = bp.get_inventory(defines.inventory.item_main)
    if item_inventory then
      bp = item_inventory[bp.active_index]
    else
      return
    end
  end

  return bp
end

function M.on_player_setup_blueprint(event)
  local blueprint = get_blueprint(event)
  if blueprint == nil then
    return
  end

  local entities = blueprint.get_blueprint_entities()
  if entities == nil then
    return
  end

  for _, entity in ipairs(entities) do
    if entity.name == "network-chest" then
      local real_entity = event.surface.find_entity(
        "network-chest",
        entity.position
      )
      if real_entity ~= nil then
        local chest_info = GlobalState.get_chest_info(real_entity.unit_number)
        if chest_info ~= nil then
          blueprint.set_blueprint_entity_tag(
            entity.entity_number,
            "requests",
            chest_info.requests
          )
        end
      end
    elseif constants.NETWORK_TANK_NAMES[entity.name] ~= nil then
      local real_entity = event.surface.find_entity(
        entity.name,
        entity.position
      )
      if real_entity ~= nil then
        local tank_info = GlobalState.get_tank_info(real_entity.unit_number)
        if tank_info ~= nil and tank_info.config ~= nil then
          blueprint.set_blueprint_entity_tag(
            entity.entity_number,
            "config",
            tank_info.config
          )
        end
      end
    end
  end
end

function M.on_entity_settings_pasted(event)
  local source = event.source
  local dest = event.destination

  -- See if we manage the destination entity
  local dst_info = GlobalState.entity_info_get(dest.unit_number)
  if dst_info == nil then
    return
  end

  -- REVISIT: I think I can do this with a metatable...
  -- get management functions
  local dst_func = GlobalState.get_service_task(dst_info.service_type)
  if dst_func == nil then
    return
  end

  -- see if we can promote this to a clone op
  if source.name == dest.name and type(dst_func.clone) == "function" then
    local src_info = GlobalState.entity_info_get(source.unit_number)
    if src_info ~= nil then
      dst_func.clone(dst_info, src_info)
      return
    end
  end

  -- try to paste settings
  if type(dst_func.paste) == "function" then
    dst_func.paste(dst_info, source)
    return
  end
end


--[[
This is the handler for the "new" requester-only chest.
Fills the chest with one item (filter slot 1), respecting the bar.

NOT USED RIGHT NOW
]]
local function update_network_chest_requester(info)
  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED
  local inv = info.entity.get_output_inventory()
  local contents = inv.get_contents()

  -- satisfy requests (pull into contents)
  for _, req in pairs(info.requests) do
    if req.type == "take" then
      local n_have = contents[req.item] or 0
      local n_innet = GlobalState.get_item_count(req.item)
      local n_avail = math.max(0, n_innet - (req.limit or 0))
      local n_want = req.buffer
      if n_want > n_have then
        local n_transfer = math.min(n_want - n_have, n_avail)
        if n_transfer > 0 then
          -- it may not fit in the chest due to other reasons
          n_transfer = inv.insert({name=req.item, count=n_transfer})
          if n_transfer > 0 then
            status = GlobalState.UPDATE_STATUS.UPDATED
            GlobalState.set_item_count(req.item, n_innet - n_transfer)

            --[[ If we filled the entire buffer AND there is enough in the net for another buffer, then
            we are probably not requesting enough. Up the buffer size by 2.
            ]]
            if n_transfer == req.buffer and n_innet > n_transfer * 4 then
              req.buffer = req.buffer + 2
            end
          end
        else
          GlobalState.missing_item_set(req.item, info.entity.unit_number, n_want - n_have)
        end
      end
    end
  end

  return status
end


-------------------------------------------
-- GUI Section -- needs to move into GUI files
-------------------------------------------

function M.on_gui_click(event)
  -- log the gui click
  --local el = event.element
  --game.print(string.format("on_gui_click: name=[%s] type=[%s]", el.name, el.type))

  UiHandlers.handle_generic_gui_event(event, "on_gui_click")
end

function M.on_gui_text_changed(event)
  UiHandlers.handle_generic_gui_event(event, "on_gui_text_changed")
end

function M.on_gui_checked_state_changed(event)
  UiHandlers.handle_generic_gui_event(event, "on_gui_checked_state_changed")
end

function M.on_gui_elem_changed(event)
  UiHandlers.handle_generic_gui_event(event, "on_gui_elem_changed")
end

function M.on_gui_confirmed(event)
  UiHandlers.handle_generic_gui_event(event, "on_gui_confirmed")
end

function M.on_gui_selected_tab_changed(event)
  UiHandlers.handle_generic_gui_event(event, "on_gui_selected_tab_changed")
end

function M.on_gui_selection_state_changed(event)
  UiHandlers.handle_generic_gui_event(event, "on_gui_selection_state_changed")
end

function M.add_take_btn_enabled()
  local takes = GlobalState.get_chest_info(global.mod.network_chest_gui.entity
    .unit_number).takes
  return #takes == 0 or M.is_request_valid(takes[#takes])
end

function M.add_give_btn_enabled()
  local gives = GlobalState.get_chest_info(global.mod.network_chest_gui.entity
    .unit_number).gives
  return #gives == 0 or M.is_request_valid(gives[#gives])
end

function M.on_gui_opened(event)
  if event.gui_type == defines.gui_type.entity and event.entity.name == "network-chest" then
    local entity = event.entity
    assert(GlobalState.get_chest_info(entity.unit_number) ~= nil)

    local player = game.get_player(event.player_index)
    if player == nil then
      return
    end

    NetworkChestGui.on_gui_opened(player, entity)
  end
end

function M.on_gui_closed(event)
  local frame = event.element
  if frame ~= nil and frame.name == UiConstants.NV_FRAME then
    NetworkViewUi.on_gui_closed(event)
  elseif frame ~= nil and (frame.name == UiConstants.MAIN_FRAME_NAME or frame.name == UiConstants.MODAL_FRAME_NAME) then
    NetworkChestGui.on_gui_closed(event)
  end
end

function M.in_confirm_dialog(event)
  NetworkChestGui.in_confirm_dialog(event)
end

function M.in_cancel_dialog(event)
  NetworkChestGui.in_cancel_dialog(event)
end

function M.on_every_5_seconds(event)
  NetworkViewUi.on_every_5_seconds(event)
end

-------------------------------------------------------------------------------
-- Register Event Handlers for this module

-- create
Event.on_event(
  defines.events.on_built_entity,
  M.on_built_entity
)
Event.on_event(
  defines.events.script_raised_built,
  M.script_raised_built
)
Event.on_event(
  defines.events.on_entity_cloned,
  M.on_entity_cloned
)
Event.on_event(
  defines.events.on_robot_built_entity,
  M.on_robot_built_entity
)
Event.on_event(
  defines.events.script_raised_revive,
  M.script_raised_revive
)

-- delete
Event.on_event(
  defines.events.on_pre_player_mined_item,
  M.generic_destroy_handler
)
Event.on_event(
  defines.events.on_robot_mined_entity,
  M.generic_destroy_handler
)
Event.on_event(
  defines.events.script_raised_destroy,
  M.generic_destroy_handler
)
Event.on_event(
  defines.events.on_entity_died,
  M.on_entity_died
)
Event.on_event(
  defines.events.on_marked_for_deconstruction,
  M.on_marked_for_deconstruction
)

Event.on_event(
  defines.events.on_post_entity_died,
  M.on_post_entity_died
)

Event.on_event(
  defines.events.on_entity_settings_pasted,
  M.on_entity_settings_pasted
)

Event.on_event(
  defines.events.on_player_setup_blueprint,
  M.on_player_setup_blueprint
)

-- gui events
Event.on_event(
  defines.events.on_gui_click,
  M.on_gui_click
)
Event.on_event(
  defines.events.on_gui_opened,
  M.on_gui_opened
)
Event.on_event(
  defines.events.on_gui_closed,
  M.on_gui_closed
)
Event.on_event(
  defines.events.on_gui_text_changed,
  M.on_gui_text_changed
)
Event.on_event(
  defines.events.on_gui_elem_changed,
  M.on_gui_elem_changed
)
Event.on_event(
  defines.events.on_gui_checked_state_changed,
  M.on_gui_checked_state_changed
)
Event.on_event(
  defines.events.on_gui_confirmed,
  M.on_gui_confirmed
)
Event.on_event(
  defines.events.on_gui_selected_tab_changed,
  M.on_gui_selected_tab_changed
)
Event.on_event(
  defines.events.on_gui_selection_state_changed,
  M.on_gui_selection_state_changed
)

-- custom events
Event.on_event(
  "in_confirm_dialog",
  M.in_confirm_dialog
)
Event.on_event(
  "in_cancel_dialog",
  M.in_cancel_dialog
)

return M
