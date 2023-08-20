local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"

local M = {}

M.WIDTH = 490
M.HEIGHT = 500

--[[
  Builds the GUI for the item, fluid, and shortage tabs.
  This page contains one element named "item_flow", which is later populated with sprite-buttons.
]]
local function build_item_page(parent)
  local main_flow = parent.add({
    type = "flow",
    direction = "vertical",
  })

  local item_flow = main_flow.add({
    type = "scroll-pane",
    direction = "vertical",
    name = "item_flow", --UiConstants.NV_ITEM_FLOW,
    vertical_scroll_policy = "always",
  })
  item_flow.style.size = { width = M.WIDTH - 30, height = M.HEIGHT - 82 }

  return main_flow
end

--[[
  Builds the GUI for the limits tab.
  This page contains an element named "item_flow", which is later populated with sprite-buttons.
  It also contains a row for editing limits.

  +-----------------------------------------+
  | [I] [I] [I] [I] [I] [I] [I] [I] [I] [I] |
  ...
  | [I] [I] [I] [I] [I] [I] [I] [I] [I] [I] |
  +-----------------------------------------+
  | [i/f] [IE] [limit]               [save] | <- item
  | [i/f] [FE] [temp] [limit]        [save] | <- fluid
  +-----------------------------------------+

  It then has another row, which contains
    * an "choose-elem-button"
    * a label for the "old/current limit"
    * a "transfer to the new limit" button
    * a textbox for entering a new limit
    * a save button

  The first hack will leave out the transfer button and put the current limit
  in the new_limit textbox.
]]
local function build_limit_page(parent)
  local main_flow = parent.add({
    type = "flow",
    direction = "vertical",
  })

  local item_flow = main_flow.add({
    type = "scroll-pane",
    direction = "vertical",
    name = "item_flow",
    vertical_scroll_policy = "always",
  })
  --item_flow.style.size = { width = M.WIDTH - 30, height = M.HEIGHT - (82 + 64) }
  item_flow.style.vertically_stretchable = true
  item_flow.style.horizontally_stretchable = true

  local edit_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
    name = "edit_flow",
  })
  edit_flow.style.size = { width = M.WIDTH - 30, height = 48 }
  edit_flow.style.vertical_align = "center"
  edit_flow.style.left_padding = 4
  edit_flow.style.right_padding = 4

  -- this chooses whether we show 'item_edit_flow' or 'fluid_edit_flow'
  local dropdown = edit_flow.add({
    type = "drop-down",
    caption = "item or Fluid",
    name = "elem_type_dropdown",
    selected_index = 1,
    items = { "item", "fluid" },
    tags = { event = UiConstants.NV_LIMIT_TYPE },
  })
  --dropdown.style.horizontally_squashable = true
  dropdown.style.width = 75

  -- this gets tricky: we create the "item" and "fluid" edit stuff and hide fluid
  local item_edit_flow = edit_flow.add({
    type = "flow",
    direction = "horizontal",
    name = "item_edit",
  })
  local fluid_edit_flow = edit_flow.add({
    type = "flow",
    direction = "horizontal",
    name = "fluid_edit",
  })
  fluid_edit_flow.visible = false
  fluid_edit_flow.style.vertical_align = "center"

  -- add the item selector
  item_edit_flow.add({
    type = "choose-elem-button",
    elem_type = "item",
    name = "elem_choose",
    tooltop = { "", "Click to select an item or click an existing item above" },
    tags = { event = UiConstants.NV_LIMIT_SELECT_ITEM },
  })

  -- add the fluid selector and temperature
  fluid_edit_flow.add({
    type = "choose-elem-button",
    elem_type = "fluid",
    name = "elem_choose",
    tooltop = { "", "Click to select an item or click an existing item above" },
    tags = { event = UiConstants.NV_LIMIT_SELECT_FLUID },
  })
  fluid_edit_flow.add({
    type = "label",
    caption = "Temp",
  })
  local tf_temp = fluid_edit_flow.add({
    type = "textfield",
    text = "0",
    numeric = true,
    name = "temperature",
  })
  tf_temp.style.width = 75

  -- the current/new limit (shared)
  edit_flow.add({
    type = "label",
    caption = "Limit",
  })
  local tf_limit = edit_flow.add({
    type = "textfield",
    text = "0",
    numeric = true,
    name = "new_limit",
  })
  tf_limit.style.width = 100

  local pad = edit_flow.add({ type= "empty-widget" })
  pad.style.horizontally_stretchable = true

  -- add save button
  edit_flow.add({
    type = "sprite-button",
    sprite = "utility/enter",
    tooltip = { "", "Update limit" },
    name = "item_save",
    style = "frame_action_button",
    tags = { event = UiConstants.NV_LIMIT_SAVE },
  })

  return main_flow
end

function M.open_main_frame(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  if ui.net_view ~= nil then
    M.destroy(player_index)
    return
  end

  local player = game.get_player(player_index)
  if player == nil then
    return
  end

  GlobalState.update_queue_log()

  local width = M.WIDTH
  local height = M.HEIGHT + 32

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
  frame.style.size = { width, height }
  frame.auto_center = true

  local main_flow = frame.add({
    type = "flow",
    direction = "vertical",
  })

  local header_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  header_flow.drag_target = frame

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
  header_drag.style.horizontally_stretchable = true

  local search_enabled = false
  if search_enabled then
    header_flow.add{
      type = "textfield",
      style = "titlebar_search_textfield",
    }

    header_flow.add{
      type = "sprite-button",
      sprite = 'utility/search_white',
      hovered_sprite = 'utility/search_black',
      clicked_sprite = 'utility/search_black',
      style = "frame_action_button",
      tooltip = { "gui.search" },
      tags = { event = UiConstants.NV_SEARCH_BTN },
    }
  end

  header_flow.add {
    type = "sprite-button",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = { "gui.refresh" },
    tags = { event = UiConstants.NV_REFRESH_BTN },
  }

  header_flow.add {
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
    tags = { event = UiConstants.NV_CLOSE_BTN },
  }

  -- add tabbed stuff
  local tabbed_pane = main_flow.add {
    type = "tabbed-pane",
    tags = { event = UiConstants.NV_TABBED_PANE },
  }

  local tab_item = tabbed_pane.add { type = "tab", caption = "Items" }
  local tab_fluid = tabbed_pane.add { type = "tab", caption = "Fluids" }
  local tab_shortage = tabbed_pane.add { type = "tab", caption = "Shortages" }
  local tab_limits = tabbed_pane.add{type="tab", caption="Limits"}

  tabbed_pane.add_tab(tab_item, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_fluid, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_shortage, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_limits, build_limit_page(tabbed_pane))

  -- select "items" (not really needed, as that is the default)
  tabbed_pane.selected_tab_index = 1

  ui.net_view = {
    frame = frame,
    tabbed_pane = tabbed_pane,
  }

  M.update_items(player_index)
end

-- used when setting the active tab
local tab_idx_to_view_type = {
  "item",
  "fluid",
  "shortage",
  "limits",
}

local function get_item_localized_name(item)
  local info = game.item_prototypes[item]
  if info == nil then
    return item or "Unknown Item"
  end

  return info.localised_name
end

local function get_fluid_localized_name(fluid)
  local info = game.fluid_prototypes[fluid]
  if info == nil then
    return fluid or "Unknown Fluid"
  end

  return info.localised_name
end

local function find_sprite_path(name)
  -- need to try each prefix that we might store in the item network
  for _, pfx in ipairs({"item", "fluid"}) do
    local tmp = string.format("%s/%s", pfx, name)
    if game.is_valid_sprite_path(tmp) then
      return tmp
    end
  end
  return "item/item-unknown"
end

local function startswith(text, prefix)
  return text:find(prefix, 1, true) == 1
end

local function item_tooltip(name, count, show_transfer)
  local tooltip = {
    "",
    get_item_localized_name(name),
    ": ",
    count
  }
  if show_transfer == true then
    table.insert(tooltip, "\nLeft click to transfer to character inventory")
  end
  return tooltip
end

local function fluid_tooltip(name, temp, count)
  return {
    "",
    get_fluid_localized_name(name),
    ": ",
    string.format("%.0f", count),
    " at ",
    { "format-degrees-c", string.format("%.0f", temp) },
  }
end

function M.update_items(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local net_view = ui.net_view
  if net_view == nil then
    return
  end
  local tabbed_pane = net_view.tabbed_pane

  net_view.view_type = tab_idx_to_view_type[tabbed_pane.selected_tab_index]
  local main_flow = tabbed_pane.tabs[tabbed_pane.selected_tab_index].content
  if main_flow == nil then
    return
  end

  local item_flow = main_flow.item_flow
  if item_flow == nil then
    return
  end
  item_flow.clear()

  if net_view.view_type == "limits" then
    M.render_tab_limits(main_flow)
    return
  end

  local view_type = net_view.view_type
  local is_item = view_type == "item"

  local h_stack_def = {
    type = "flow",
    direction = "horizontal",
  }

  local rows = M.get_rows_of_items(view_type)
  for _, row in ipairs(rows) do
    local item_h_stack = item_flow.add(h_stack_def)
    for _, item in ipairs(row) do
      -- -1 is filtered out and used to mean an "add" slot
      if item.count < 0 then
        item_h_stack.add({
          type = "sprite-button",
          sprite = "utility/slot_icon_resource_black",
          tags = { event = UiConstants.NV_ITEM_SPRITE },
          -- FIXME: needs translation tag
          tooltip = { "", "Left-click with an item stack to add to the network" },
        })
      else
        local sprite_path = find_sprite_path(item.item)
        local def = {
          type = "sprite-button",
          sprite = sprite_path,
        }
        if item.temp ~= nil then
          def.tooltip = fluid_tooltip(item.item, item.temp, item.count)
        else
          def.tooltip = item_tooltip(item.item, item.count, is_item)
          if is_item then
            def.tags = { event = UiConstants.NV_ITEM_SPRITE, item = item.item }
          end
        end
        local item_view = item_h_stack.add(def)
        item_view.number = item.count
      end
    end
  end
end

function M.on_gui_click_item(event, element)
  --[[
  This handles a click on an item sprite in the item view.
  If the cursor has something in it, then the cursor content is dumped into the item network.
  If the cursor is empty then we grab something from the item network.
    left-click grabs one item.
    shift + left-click grabs one stack.
    ctrl + left-click grabs it all.

  REVISIT:
    - should this transfer if clicked on an item
  ]]
  local player = game.players[event.player_index]
  if player == nil then
    return
  end
  local inv = player.get_main_inventory()

  -- if we have an empty cursor, then we are taking items, which requires a valid target
  if player.is_cursor_empty() then
    local item_name = event.element.tags.item
    if item_name == nil then
      return
    end

    local network_count = GlobalState.get_item_count(item_name)
    local stack_size = game.item_prototypes[item_name].stack_size

    if event.button == defines.mouse_button_type.left then
      -- shift moves a stack, non-shift moves 1 item
      local n_transfer = 1
      if event.shift then
        n_transfer = stack_size
      elseif event.control then
        n_transfer = network_count
      end
      -- move one item or stack to player inventory
      n_transfer = math.min(network_count, n_transfer)
      if n_transfer > 0 then
        local n_moved = inv.insert({name = item_name, count = n_transfer})
        if n_moved > 0 then
          GlobalState.set_item_count(item_name, network_count - n_moved)
          -- update the number overlay and the tooltip
          element.number = GlobalState.get_item_count(item_name)
          element.tooltip = item_tooltip(item_name, element.number, true)
        end
      end
    end
    return

  else
    -- There is a stack in the cursor. Deposit it.
    local cs = player.cursor_stack
    if not cs or not cs.valid_for_read then
      return
    end

    -- don't deposit tracked entities (can be unique)
    if cs.item_number ~= nil then
      game.print(string.format("Refusing to deposit %s", cs.name))
      return
    end

    if event.button == defines.mouse_button_type.left then
      GlobalState.increment_item_count(cs.name, cs.count)
      cs.clear()
      player.clear_cursor()
      M.update_items(event.player_index)
    end
  end
end

function M.get_limit_items()
  local limits = GlobalState.get_limits()

  -- add a limit for any item/fluid that we have that doesn't have a limit
  for name, _ in pairs(GlobalState.get_items()) do
    if limits[name] == nil then
      limits[name] = GlobalState.get_default_limit(name)
    end
  end
  for name, temp_info in pairs(GlobalState.get_fluids()) do
    for temp, _ in pairs(temp_info) do
      local key = GlobalState.fluid_temp_key_encode(name, temp)
      if limits[key] == nil then
        limits[key] = GlobalState.get_default_limit(key)
      end
    end
  end
  return limits
end

function M.render_tab_limits(main_flow)
  -- create the item grid display
  local item_flow = main_flow.item_flow

  item_flow.clear()

  --[[
    Strategy: anything in the network appears in the list. If there is no limit, then show infinity.
    Any item/liquid that has a limit will have an icon.
    Show one row of blank boxes that can be clicked to bring up an item selection window with a limit bar on the bottom.
  ]]

  local rows = M.get_rows_of_items("limits")
  for _, row in ipairs(rows) do
    local item_h_stack = item_flow.add({
      type = "flow",
      direction = "horizontal",
    })
    for _, item in ipairs(row) do
      local sprite_path = find_sprite_path(item.item)
      local def = {
        type = "sprite-button",
        sprite = sprite_path,
        tags = { event = UiConstants.NV_LIMIT_ITEM, item = item.item, temp=item.temp },
      }

      local tooltip
      if startswith(sprite_path, "item") then
        tooltip = item_tooltip(item.item, item.count)
      else
        tooltip = fluid_tooltip(item.item, item.temp or 10, item.count)
      end
      table.insert(tooltip, "\nLeft click to edit.\nRight click to remove/revert to defaults.")
      def.tooltip = tooltip

      local item_view = item_h_stack.add(def)
      item_view.number = item.count
    end
  end
end

-- sort so that negative numbers show up first and everything else is largest-to-smallest
local function items_list_sort(left, right)
  if left.count < 0 then
    return true
  end
  if right.count < 0 then
    return false
  end
  return left.count > right.count
end

local function limit_compare_fluid(left, right)
  if left.item < right.item then
    return true
  end
  if left.item > right.item then
    return false
  end
  return left.temp < right.temp
end

local function limit_compare_item(left, right)
  -- we want to compare in the Factorio way - by group and then name
  return left.item < right.item
end

function M.get_list_of_items(view_type)
  local items = {}

  local function add_item(item)
    if game.item_prototypes[item.item] ~= nil or game.fluid_prototypes[item.item] ~= nil then
      table.insert(items, item)
    end
  end

  if view_type == "item" then
    -- add one for dropping item stacks
    table.insert(items, { item = "empty-slot", count=-1 })
    local items_to_display = GlobalState.get_items()
    for item_name, item_count in pairs(items_to_display) do
      if item_count > 0 then
        add_item({ item = item_name, count = item_count })
      end
    end
  elseif view_type == "fluid" then
    local fluids_to_display = GlobalState.get_fluids()
    for fluid_name, fluid_temps in pairs(fluids_to_display) do
      for temp, count in pairs(fluid_temps) do
        add_item({ item = fluid_name, count = count, temp = temp })
      end
    end
  elseif view_type == "shortage" then
    -- add item shortages
    local missing = GlobalState.missing_item_filter()
    for item_name, count in pairs(missing) do
      -- sometime shortages can have invalid item names.
      add_item({ item = item_name, count = count })
    end

    -- add fluid shortages
    missing = GlobalState.missing_fluid_filter()
    for fluid_key, count in pairs(missing) do
      local fluid_name, temp = GlobalState.fluid_temp_key_decode(fluid_key)
      add_item({ item = fluid_name, count = count, temp = temp })
    end
  elseif view_type == "limits" then
    local fluids = {}
    for item_name, count in pairs(M.get_limit_items()) do
      local nn, tt = GlobalState.fluid_temp_key_decode(item_name)
      if tt ~= nil then
        table.insert(fluids, { item = nn, temp = tt, count = count })
      else
        table.insert(items, { item = item_name, count = count })
      end
    end
    table.sort(fluids, limit_compare_fluid)
    table.sort(items, limit_compare_item)
    table.insert(fluids, "break")
    for _, ent in ipairs(items) do
      table.insert(fluids, ent)
    end
    return fluids
  end

  table.sort(items, items_list_sort)

  return items
end

function M.get_rows_of_items(view_type)
  local items = M.get_list_of_items(view_type)
  local max_row_count = 10
  local rows = {}
  local row = {}

  for _, item in ipairs(items) do
    if type(item) == "string" then
      if #row > 0 then
        table.insert(rows, row)
        row = {}
      end
    elseif #row == max_row_count then
      table.insert(rows, row)
      row = {}
      table.insert(row, item)
    else
      table.insert(row, item)
    end
  end

  if #row > 0 then
    table.insert(rows, row)
  end
  return rows
end

function M.destroy(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  if ui.net_view ~= nil then
    ui.net_view.frame.destroy()
    ui.net_view = nil
  end
end

function M.on_gui_closed(event)
  M.destroy(event.player_index)
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
  local ui = GlobalState.get_ui_state(event.player_index)
  if ui.net_view == nil then
    return
  end
  if ui.net_view.view_type ~= "limits" then
    return
  end
  local tabbed_pane = ui.net_view.tabbed_pane
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
  edit_flow.elem_type_dropdown.selected_index = type_idx
end

local function limit_set_edit_item(edit_flow, item_name, item_temp)
  if item_name ~= nil then

    local prot = game.item_prototypes[item_name]
    if prot ~= nil then
      local item_limit = GlobalState.get_limit(item_name)
      game.print(string.format("limit_set_edit_item: item [%s] limit=%s", item_name, item_limit))
      limit_set_edit_type(edit_flow, 1)
      edit_flow.item_edit.elem_choose.elem_value = item_name
      edit_flow.new_limit.text = string.format("%s", item_limit)
      edit_flow.new_limit.select(1, 0)
    else
      prot = game.fluid_prototypes[item_name]
      if prot ~= nil then
        if item_temp == nil then
          item_temp = prot.default_temperature
        end
        local key = GlobalState.fluid_temp_key_encode(item_name, item_temp)
        local item_limit = GlobalState.get_limit(key)
        game.print(string.format("limit_set_edit_item: fluid [%s] limit=%s", key , item_limit))
        limit_set_edit_type(edit_flow, 2)
        edit_flow.fluid_edit.elem_choose.elem_value = item_name
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
  if player == nil then
    return
  end

  limit_set_edit_item(edit_flow, edit_flow.item_edit.elem_choose.elem_value)
end

-- the selection change. refresh the current limit text box
function M.on_limit_fluid_elem_changed(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil then
    return
  end

  limit_set_edit_item(edit_flow, edit_flow.fluid_edit.elem_choose.elem_value)
end

-- read the limit and save to the limits structure
function M.on_limit_save(event, element)
  local player, edit_flow = limit_event_prep(event)
  if player == nil then
    return
  end

  if edit_flow.item_edit.visible then
    -- item
    game.print(string.format("setting item %s limit %s",
      edit_flow.item_edit.elem_choose.elem_value,
      edit_flow.new_limit.text))
    if GlobalState.set_limit(edit_flow.item_edit.elem_choose.elem_value, edit_flow.new_limit.text) then
      M.update_items(player.index)
    end
  else
    -- fluid
    local fluid_name = edit_flow.fluid_edit.elem_choose.elem_value
    local fluid_temp = tonumber(edit_flow.fluid_edit.temperature.text)
    if fluid_name ~= nil and fluid_temp ~= nil then
      local key = GlobalState.fluid_temp_key_encode(fluid_name, fluid_temp)
      game.print(string.format("setting fluid %s limit %s", key, edit_flow.new_limit.text))
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
  if player == nil then
    return
  end

  limit_set_edit_type(edit_flow, edit_flow.elem_type_dropdown.selected_index)
end

return M
