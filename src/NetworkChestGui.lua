local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Constants = require "src.constants"

local M = {}

function M.on_gui_opened(player, chest_entity)
  local ui = GlobalState.get_ui_state(player.index)

  -- delete previous frames if exist
  M.reset(player, ui)

  local chest_info = GlobalState.get_chest_info(chest_entity.unit_number)
  if chest_info == nil then
    return
  end
  local chest_requests = chest_info.requests
  local requests = M.get_ui_requests_from_chest_requests(chest_requests)

  local width = 600
  local height = 500

  local frame = player.gui.screen.add({
    type = "frame",
    caption = "Configure Network Chest",
    name = UiConstants.MAIN_FRAME_NAME,
  })
  player.opened = frame
  frame.style.size = { width, height }
  frame.auto_center = true

  local requests_flow = frame.add({ type = "flow", direction = "vertical" })
  local requests_header_flow = requests_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  requests_header_flow.add({
    type = "button",
    caption = "Add Item",
    tags = { event = UiConstants.ADD_ITEM_BTN_NAME },
  })
  requests_header_flow.add({
    type = "button",
    caption = "Auto",
    tags = { event = UiConstants.AUTO_ITEM_BTN_NAME },
  })
  -- add_request_btn.style.width = 40
  local requests_scroll = requests_flow.add({
    type = "scroll-pane",
    direction = "vertical",
    vertical_scroll_policy = "always",
  })
  requests_scroll.style.size = { width = width - 30, height = height - 160 }

M.log_chest_state(chest_entity, chest_info)

  if #requests == 0 then
    M.add_autochest_element(chest_entity, chest_info, requests_scroll)
  else
    for _, request in ipairs(requests) do
      M.add_request_element(request, requests_scroll)
    end
  end

  -- edit window
  local edit_flow = requests_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  edit_flow.style.vertical_align = "center"

  edit_flow.add({
    type = "drop-down",
    caption = "Request or Provide",
    name = "edit_dropdown",
    selected_index = 1,
    items = { "Request", "Provide" },
  })
  edit_flow.add({
    name = "edit_item",
    type = "choose-elem-button",
    elem_type = "item",
  })
  --edit_flow.add({ type = "label", caption = "when network has more than" })
  edit_flow.add({ type = "label", caption = "Limit:" })
  local edit_limit = edit_flow.add({
    name = "edit_limit",
    type = "textfield",
    text = "0",
  })
  edit_limit.style.width = 50
  edit_flow.add({ type = "label", caption = "Buffer:" })
  local edit_buffer = edit_flow.add({
    name = "edit_buffer",
    type = "textfield",
    text = "5",
  })
  edit_buffer.style.width = 50

  local pad = edit_flow.add({ type= "empty-widget" })
  pad.style.horizontally_stretchable = true

  -- add save button
  edit_flow.add({
    type = "sprite-button",
    sprite = "utility/enter",
    tooltip = { "", "Update limit" },
    name = "edit_save",
    style = "frame_action_button",
    --tags = { event = UiConstants.NV_LIMIT_SAVE },
  })

  local end_button_flow = requests_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  end_button_flow.add({
    type = "button",
    caption = "Save",
    tags = { event = UiConstants.SAVE_NETWORK_CHEST_BTN_NAME },
  })
  end_button_flow.add({
    type = "button",
    caption = "Cancel",
    tags = { event = UiConstants.CANCEL_NETWORK_CHEST_BTN_NAME },
  })

  ui.network_chest = {
    chest_entity = chest_entity,
    requests = requests,
    requests_scroll = requests_scroll,
    frame = frame,
  }
end

function M.log_chest_state(entity, info)
  local inv = entity.get_output_inventory()
  GlobalState.log_entity("Chest:", entity)
  game.print(string.format(" - chest has %s requests, bar=%s/%s", #info.requests, inv.get_bar(), #inv))
  if inv.is_filtered() then
    for i = 1, #inv do
      local filt = inv.get_filter(i)
      if filt ~= nil then
        game.print(string.format("  [%s] %s", i, filt))
      end
    end
  end
end

local function add_item_button(parent, cur_row, item_name, count, seconds)
  local tooltip = {
    "",
    game.item_prototypes[item_name].localised_name,
  }
  if cur_row == nil or #cur_row.children == 10 then
    cur_row = parent.add({
      type = "flow",
      direction = "horizontal",
    })
  end

  if count ~= nil then
    table.insert(tooltip, ": ")
    table.insert(tooltip, count)
  elseif seconds ~= nil then
    table.insert(tooltip, ": ")
    table.insert(tooltip, string.format("last provided %d seconds ago", seconds))
  end
  local btn = cur_row.add({
    type = "sprite-button",
    sprite = "item/" .. item_name,
    --caption = "Seen 5 seconds ago",
    tooltip = tooltip,
  })
  if count ~= nil then
    btn.number = count
  end
  return cur_row
end

function M.add_autochest_element(entity, info, frame)
  frame.add({
    type = "label",
    caption = "This chest is in auto-provider mode.",
  })

  local inv = entity.get_output_inventory()
  local contents = inv.get_contents()
  local is_locked = (inv.get_bar() < #inv)
  if is_locked then
    frame.add({
      type = "label",
      caption = "It is locked due to the following items.",
    })
    local subframe
    for i = inv.get_bar(), #inv do
      if inv[i].valid_for_read then
        local name = inv[i].name
        subframe = add_item_button(frame, subframe, name, contents[name])
      end
    end
    if inv.get_bar() > 1 then
      frame.add({
        type = "label",
        caption = "It is accepting the following items.",
      })
      subframe = nil
      for i = 1, inv.get_bar() do
        local name = inv.get_filter(i)
        if name ~= nil then
          subframe = add_item_button(frame, subframe, name, GlobalState.get_insert_count(name))
        end
      end
    else
      frame.add({
        type = "label",
        caption = "It is not accepting items.",
      })
    end
  else
    frame.add({
      type = "label",
      caption = "It is currently unlocked.",
    })
  end
  if info.recent_items and next(info.recent_items) ~= nil then
    frame.add({
      type = "label",
      caption = "It has recently provided the following items to the network.",
    })
    local subframe
    for name, tick in pairs(info.recent_items) do
      subframe = add_item_button(frame, subframe, name, nil, (game.tick - tick) / 60)
    end
  end
end

function M.add_request_element(request, parent)
  local flow = parent.add({
    type = "flow",
    direction = "horizontal",
    name = request.id,
  })
  flow.style.vertical_align = "center"
  flow.style.right_padding = 8
  flow.style.left_padding = 8

  flow.add({ name = UiConstants.BEFORE_ITEM_NAME, type = "label" })

  local choose_item_button = flow.add({
    name = UiConstants.CHOOSE_ITEM_NAME,
    type = "choose-elem-button",
    elem_type = "item",
    tags = { event = UiConstants.EDIT_REQUEST_BTN, request_id = request.id },
  })
  choose_item_button.locked = true

  flow.add({ name = UiConstants.AFTER_ITEM_NAME, type = "label" })

  --[[
  local edit_btn = flow.add({
    type = "button",
    caption = "Edit",
    tooltip = { "" , "Edit request" },
    tags = { event = UiConstants.EDIT_REQUEST_BTN, request_id = request.id },
  })
  edit_btn.style.width = 60
]]
  local pad = flow.add({ type= "empty-widget" })
  pad.style.horizontally_stretchable = true

  flow.add {
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
    tooltip = { "" , "Delete request" },
    tags = { event = UiConstants.REMOVE_REQUEST_BTN, request_id = request.id },
  }

--[[  local remove_btn = flow.add({
    type = "button",
    caption = "x",
    tooltip = { "" , "Delete request" },
    tags = { event = UiConstants.REMOVE_REQUEST_BTN, request_id = request.id },
  })
  remove_btn.style.width = 40
]]
  M.update_request_element(request, flow)
end

function M.update_request_element(request, element)
  element[UiConstants.CHOOSE_ITEM_NAME].elem_value = request.item

  local before_item_label
  local after_item_label
  if request.type == "take" then
    before_item_label = "Request"
    after_item_label = string.format(
      "when network has more than %d and buffer %d.",
      request.limit,
      request.buffer
    )
  else
    before_item_label = "Provide"
    after_item_label = string.format(
      "when network has less than %d and buffer %d.",
      request.limit,
      request.buffer
    )
  end
  element[UiConstants.BEFORE_ITEM_NAME].caption = before_item_label
  element[UiConstants.AFTER_ITEM_NAME].caption = after_item_label
end

function M.get_ui_requests_from_chest_requests(chest_requests)
  local requests = {}
  for _, request in ipairs(chest_requests) do
    table.insert(requests, {
      type = request.type,
      id = GlobalState.rand_hex(16),
      item = request.item,
      buffer = request.buffer,
      limit = request.limit,
    })
  end
  return requests
end

function M.reset(player, ui)
  M.destroy_frame(player, UiConstants.MODAL_FRAME_NAME)
  M.destroy_frame(player, UiConstants.MAIN_FRAME_NAME)
  ui.network_chest = nil
end

function M.destroy_frame(player, frame_name)
  local frame = player.gui.screen[frame_name]
  if frame ~= nil then
    frame.destroy()
  end
end

function M.on_gui_closed(event)
  local ui = GlobalState.get_ui_state(event.player_index)
  local close_type = ui.close_type
  ui.close_type = nil


  local element = event.element
  if element == nil then
    return
  end

  local player = game.get_player(event.player_index)
  if player == nil then
    return
  end

  if close_type == nil then
    M.reset(player, ui)
  elseif element.name == UiConstants.MAIN_FRAME_NAME then
    -- make sure that the modal wasn't just opened
    if ui.network_chest.modal == nil then
      M.close_main_frame(player, true)
    end
  elseif element.name == UiConstants.MODAL_FRAME_NAME then
    M.close_modal(player)
  end
end

function M.close_main_frame(player, save_requests)
  local ui = GlobalState.get_ui_state(player.index)
  if save_requests then
    local requests = {}
    for _, request in ipairs(ui.network_chest.requests) do
      table.insert(requests,
        {
          id = request.id,
          type = request.type,
          item = request.item,
          buffer = request.buffer,
          limit = request.limit,
        })
    end
    if ui.network_chest.chest_entity.valid then
      GlobalState.set_chest_requests(
        ui.network_chest.chest_entity.unit_number,
        requests
      )
    end
  end

  if ui.network_chest.modal ~= nil then
    ui.network_chest.modal.frame.destroy()
  end
  ui.network_chest.frame.destroy()
  ui.network_chest = nil
end

function M.close_modal(player)
  local ui = GlobalState.get_ui_state(player.index)
  if ui.network_chest == nil then
    return
  end
  local modal = ui.network_chest.modal
  if modal == nil then
    return
  end
  modal.frame.destroy()
  ui.network_chest.modal = nil
  player.opened = ui.network_chest.frame
end

function M.get_request_by_id(player, request_id)
  if request_id == nil then
    return nil
  end

  local ui = GlobalState.get_ui_state(player.index).network_chest

  for _, request in ipairs(ui.requests) do
    if request.id == request_id then
      return request
    end
  end

  return nil
end

function M.open_modal(player, type, request_id)
  local default_is_take = true
  local default_item = nil
  local default_buffer = nil
  local default_limit = nil

  local request = M.get_request_by_id(player, request_id)
  if request ~= nil then
    default_is_take = request.type == "take"
    default_item = request.item
    default_buffer = request.buffer
    default_limit = request.limit
  end

  local ui = GlobalState.get_ui_state(player.index)
  if ui.network_chest.modal ~= nil then
    M.close_modal(player)
  end

  local width = 400
  local height = 300

  local frame = player.gui.screen.add({
    type = "frame",
    caption = type == "add" and "Add Item" or "Edit Item",
    name = UiConstants.MODAL_FRAME_NAME,
  })

  local main_flow = frame.add({
    type = "flow",
    direction = "vertical",
  })

  local type_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  type_flow.add({ type = "label", caption = "Type:" })
  local choose_take_btn = type_flow.add({
    type = "radiobutton",
    state = default_is_take,
    tags = { event = UiConstants.MODAL_CHOOSE_TAKE_BTN_NAME },
  })
  type_flow.add({ type = "label", caption = "Request" })
  local choose_give_btn = type_flow.add({
    type = "radiobutton",
    state = not default_is_take,
    tags = { event = UiConstants.MODAL_CHOOSE_GIVE_BTN_NAME },
  })
  type_flow.add({ type = "label", caption = "Provide" })

  local item_flow = main_flow.add({ type = "flow", direction = "horizontal" })
  item_flow.add({ type = "label", caption = "Item:" })
  local item_picker = item_flow.add({
    type = "choose-elem-button",
    elem_type = "item",
    elem_value = default_item,
    tags = { event = UiConstants.MODAL_ITEM_PICKER },
  })
  item_picker.elem_value = default_item

  local buffer_flow = main_flow.add({ type = "flow", direction = "horizontal" })
  buffer_flow.add({ type = "label", caption = "Buffer:" })
  local buffer_size_input = buffer_flow.add({
    type = "textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    tags = { event = UiConstants.MODAL_BUFFER_FIELD },
  })
  if default_buffer ~= nil then
    buffer_size_input.text = string.format("%s", default_buffer)
  end
  buffer_size_input.style.width = 50

  local limit_flow = main_flow.add({ type = "flow", direction = "horizontal" })
  limit_flow.add({ type = "label", caption = "Limit:" })
  local limit_input = limit_flow.add({
    type = "textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    tags = { event = UiConstants.MODAL_LIMIT_FIELD },
  })
  if default_limit ~= nil then
    limit_input.text = string.format("%s", default_limit)
  end
  limit_input.style.width = 50

  local save_cancel_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  save_cancel_flow.add({
    type = "button",
    caption = "Save",
    tags = {
      event = UiConstants.MODAL_CONFIRM_BTN_NAME,
      type = type,
      request_id = request_id,
    },
  })
  save_cancel_flow.add({
    type = "button",
    caption = "Cancel",
    tags = {
      event = UiConstants.MODAL_CANCEL_BTN_NAME,
      type = type,
      request_id = request_id,
    },
  })

  frame.style.size = { width, height }
  frame.auto_center = true

  local modal = {
    frame = frame,
    choose_take_btn = choose_take_btn,
    choose_give_btn = choose_give_btn,
    buffer_size_input = buffer_size_input,
    limit_input = limit_input,
    request_type = default_is_take and "take" or "give",
    item = default_item,
    buffer = default_buffer,
    limit = default_limit,
    disable_set_defaults_on_change = type == "edit",
    modal_type = type,
    request_id = request_id, -- only defined for edit events
  }

  -- the order is is important since setting player.opened = frame
  -- will trigger a "on_gui_closed" event that needs to be ignored.
  ui.network_chest.modal = modal
  ui.close_type = "open modal"
  player.opened = frame
end

function M.in_confirm_dialog(event)
  local ui = GlobalState.get_ui_state(event.player_index)
  ui.close_type = "confirm"
end

function M.in_cancel_dialog(event)
  local ui = GlobalState.get_ui_state(event.player_index)
  ui.close_type = "cancel"
end

local Modal = {}

function Modal.set_default_buffer_and_limit(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local modal = ui.network_chest.modal

  if not modal.disable_set_defaults_on_change then
    Modal.set_default_buffer(player_index)
    Modal.set_default_limit(player_index)
  end
end

function Modal.set_default_buffer(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local modal = ui.network_chest.modal
  local item = modal.item
  local request_type = modal.request_type
  if item ~= nil and request_type ~= nil then
    local stack_size = game.item_prototypes[item].stack_size
    local buffer = math.min(50, stack_size)
    Modal.set_buffer(buffer, modal)
  end
end

function Modal.set_default_limit(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local modal = ui.network_chest.modal
  local item = modal.item
  local request_type = modal.request_type
  if item ~= nil and request_type ~= nil then
    local stack_size = game.item_prototypes[item].stack_size
    local limit
    if request_type == "take" then
      limit = 0
    else
      limit = math.min(50, stack_size)
    end
    Modal.set_limit(limit, modal)
  end
end

function Modal.set_buffer(buffer, modal)
  modal.buffer = buffer
  modal.buffer_size_input.text = string.format("%d", buffer)
end

function Modal.set_limit(limit, modal)
  modal.limit = limit
  modal.limit_input.text = string.format("%d", limit)
end

function Modal.try_to_auto(player_index)
  --local player = game.get_player(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local chest_ui = ui.network_chest
  local entity = chest_ui.chest_entity

  -- the chest must still exist
  if entity == nil or not entity.valid then
    return
  end

  game.print(string.format("try_to_auto %s @ (%s,%s)", entity.name,
    entity.position.x, entity.position.y))

  -- we only deal with requests/takes right now
  local auto_request, auto_provide = GlobalState.auto_network_chest(entity)
  if auto_request ~= nil and next(auto_request) ~= nil then
    game.print("AUTO Requests")
    for name, count in pairs(auto_request) do
      game.print(string.format("  %s %s", name, count))
    end
  end
  if auto_provide ~= nil and next(auto_provide) ~= nil then
    game.print("AUTO Provide")
    for name, count in pairs(auto_provide) do
      game.print(string.format("  %s %s", name, count))
    end
  end

  local chest_req = {}
  for item_name, item_count in pairs(auto_request) do
    table.insert(chest_req, {
      type = "take",
      item = item_name,
      buffer = item_count,
      limit = 0,
      })
  end

  -- print the chest_req
  game.print("Chest Req")
  for _, rr in ipairs(chest_req) do
    game.print(string.format(" -- %s @ %s", rr.item, rr.buffer))
  end
  game.print("Old Req")
  for _, old_req in ipairs(chest_ui.requests) do
    game.print(string.format(" -- type=%s item=%s id=%s",
      old_req.type, old_req.item, old_req.id))
  end

  -- convert to the ui format
  local ui_req = M.get_ui_requests_from_chest_requests(chest_req)
  game.print("UI Req")
  for _, rr in ipairs(ui_req) do
    --local edit_req_id = ""
    local edit_mode = "add"

    -- see if this item has already been requested
    for _, old_req in ipairs(chest_ui.requests) do
      --game.print(string.format(" -- old_req type=%s item=%s id=%s",
      --  old_req.type, old_req.item, old_req.id))

      if old_req.item == rr.item then
        if rr.buffer <= old_req.buffer then
          -- no change
          edit_mode = "none"
        else
          edit_mode = "edit"
        end
        break
      end
    end
    game.print(string.format(" -- mode=%s type=%s item=%s buffer=%s limit=%s id=%s",
      edit_mode,
      rr.type, rr.item, rr.buffer, rr.limit, rr.id))

    --table.insert(chest_ui.requests, request)
    --M.add_request_element(request, chest_ui.requests_scroll)
  end

--[[
  -- make sure item request does not already exist
  for _, request in ipairs(chest_ui.requests) do
    if (
        modal_type == "add"
        or modal_type == "edit" and request.id ~= request_id
      ) and request.item == item then
      return
    end
  end
]]
end

function Modal.try_to_confirm(player_index)
  local player = game.get_player(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local chest_ui = ui.network_chest
  local modal = chest_ui.modal

  local modal_type = modal.modal_type
  local request_id = modal.request_id
  local request_type = modal.request_type
  local item = modal.item
  local buffer = modal.buffer
  local limit = modal.limit

  if request_type == nil or item == nil or buffer == nil or limit == nil then
    return
  end

  game.print(string.format("try_to_confirm: rtype=%s item=%s buffer=%s limit=%s", request_type, item, buffer, limit))

  -- "take" must buffer something, "give" can have no buffer.
  -- give limit=0 means use global limit
  if buffer < 0 or limit < 0 or (request_type == "take" and buffer <= 0) then
    return
  end

  -- make sure item request does not already exist
  for _, request in ipairs(chest_ui.requests) do
    if (
        modal_type == "add"
        or modal_type == "edit" and request.id ~= request_id
      ) and request.item == item then
      return
    end
  end

  -- make sure request size does not exceed chest size
  local used_slots = 0
  for _, request in ipairs(chest_ui.requests) do
    local stack_size = game.item_prototypes[request.item].stack_size
    local slots = math.max(1, math.ceil(request.buffer / stack_size))
    used_slots = used_slots + slots
  end
  assert(used_slots <= Constants.NUM_INVENTORY_SLOTS)
  local new_inv_slots = math.ceil(buffer /
    game.item_prototypes[item].stack_size)
  if used_slots + new_inv_slots > Constants.NUM_INVENTORY_SLOTS then
    return
  end

  if modal_type == "add" then
    local request = {
      id = GlobalState.rand_hex(16),
      type = request_type,
      item = item,
      buffer = buffer,
      limit = limit,
    }
    table.insert(chest_ui.requests, request)
    M.add_request_element(request, chest_ui.requests_scroll)
  elseif modal_type == "edit" then
    local request = M.get_request_by_id(player,
      request_id
    )
    if request ~= nil then
      request.type = request_type
      request.item = item
      request.buffer = buffer
      request.limit = limit
    end
    local request_elem = chest_ui.requests_scroll[request_id]
    M.update_request_element(request, request_elem)
  end
  ui.close_type = "confirm_request"
  player.opened = chest_ui.frame
end

M.Modal = Modal

return M
