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

  -- this provides the scrollable area
  local vert_flow = main_flow.add({
    type = "scroll-pane",
    direction = "vertical",
    name = "vert_flow",
    vertical_scroll_policy = "always",
  })
  vert_flow.style.size = { width = M.WIDTH - 30, height = M.HEIGHT - 82 }

  -- this is the table that contains all the items
  local item_flow = vert_flow.add({
    type = "table",
    name = "item_flow",
    style = "slot_table",
    column_count = 10,
  })
  item_flow.style.horizontal_spacing = 4
  item_flow.style.vertically_stretchable = true
  item_flow.style.horizontally_stretchable = true

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

  local vert_flow = main_flow.add({
    type = "scroll-pane",
    direction = "vertical",
    name = "vert_flow",
    vertical_scroll_policy = "always",
    style = "scroll_pane",
  })
  --vert_flow.style.size = { width = M.WIDTH - 30, height = M.HEIGHT - (82 + 64) }
  vert_flow.style.vertically_stretchable = true
  vert_flow.style.horizontally_stretchable = true

  -- this is the table that contains all the items
  local item_table = vert_flow.add({
    type = "table",
    name = "item_flow",
    style = "slot_table",
    column_count = 10,
  })
  item_table.style.horizontal_spacing = 4
  item_table.style.vertically_stretchable = true
  item_table.style.horizontally_stretchable = true

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

-------------------------------------------------------------------------------

local function build_test_page(parent)
  local main_flow = parent.add({
    type = "flow",
    direction = "vertical",
    --style = "entity_frame_wihtout_right_padding",
  })


  local crafting_frame = main_flow.add({
    type = "frame",
    direction = "vertical",
    style = "crafting_frame",
  })

  --[[
  local tabbed_filter = crafting_frame.add({
    type = "tabbed-pane",
    style = "filter_group_tab",
  }


  local tab_item = tabbed_pane.add { type = "tab", caption = "Items" }
  local tab_fluid = tabbed_pane.add { type = "tab", caption = "Fluids" }
  local tab_shortage = tabbed_pane.add { type = "tab", caption = "Shortages" }
  local tab_limits = tabbed_pane.add{type="tab", caption="Limits"}
  local tab_test = tabbed_pane.add{type="tab", caption="Test"}

  tabbed_pane.add_tab(tab_item, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_fluid, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_shortage, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_limits, build_limit_page(tabbed_pane))
  tabbed_pane.add_tab(tab_test, build_test_page(tabbed_pane))

  -- select "items" (not really needed, as that is the default)
  tabbed_pane.selected_tab_index = 1

]]

  --[[
  main_flow.add({
    type = "label",
    caption = "Normal",
    style = "entity_frame",
  })

  local entity_flow = main_flow.add({
    type = "flow",
    direction = "vertical",
    style = "deep_frame_in_shallow_frame",
  })

  local entity_flow = main_flow.add({
    type = "flow",
    direction = "vertical",
    --style = "entity_frame_wihtout_right_padding",
  })
]]

  local item_tab = main_flow.add({
    type = "table",
    name = "item_table",
    style = "slot_table",
    column_count = 10
  })
  --item_tab.style.vertically_stretchable = true
  --item_tab.style.horizontally_stretchable = true

  for _ = 1, 16 do
    item_tab.add({
      type = "sprite-button",
      sprite = "item/iron-ore",
      --style = "recipe_slot_button",
      style = "inventory_slot",
    })
  end

  item_tab.add({
    type = "label",
    caption = "\nThis is a label\n",
  })

  item_tab.add({
    type = "sprite-button",
    sprite = "utility/slot_icon_resource",
    style = "yellow_slot_button",
  })

  for _ = 1, 5 do
    item_tab.add({
      type = "sprite-button",
      sprite = "utility/slot_icon_resource",
      style = "inventory_slot",
    })
  end
  item_tab.add({
    type = "sprite-button",
    sprite = "utility/slot_icon_resource",
    style = "filter_inventory_slot",
  })
  item_tab.add({
    type = "sprite-button",
    sprite = "utility/slot_icon_result",
    style = "inventory_slot",
  })
  item_tab.add({
    type = "sprite-button",
    sprite = "utility/slot_icon_result_black", --
    style = "inventory_slot",
  })
  item_tab.add({
    type = "sprite-button",
    sprite = "utility/slot", -- blank of the correct size
    style = "inventory_slot",
  })
  item_tab.add({
    type = "sprite-button",
    sprite = "utility/set_bar_slot",
    style = "inventory_slot",
  })

  if true then
    return main_flow
  end

  local item_flow = main_flow.add({
    type = "scroll-pane",
    direction = "vertical",
    name = "item_flow",
    vertical_scroll_policy = "always",
  })
  --item_flow.style.size = { width = M.WIDTH - 30, height = M.HEIGHT - (82 + 64) }
  item_flow.style.vertically_stretchable = true
  item_flow.style.horizontally_stretchable = true

  local function add_row(sprite)
  end


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

-------------------------------------------------------------------------------

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

  -- important elements
  local elems = {}

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

  elems.network_view = frame

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

  elems.close_button = header_flow.add {
    name = "close_button",
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
    tags = { event = UiConstants.NV_CLOSE_BTN },
  }

  elems.pin_button = header_flow.add {
    name = "pin_button",
    type = "sprite-button",
    sprite = "flib_pin_white",
    hovered_sprite = "flib_pin_black",
    clicked_sprite = "flib_pin_black",
    style = "frame_action_button",
    tags = { event = UiConstants.NV_PIN_BTN },
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
  local tab_test = tabbed_pane.add{type="tab", caption="Test"}

  tabbed_pane.add_tab(tab_item, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_fluid, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_shortage, build_item_page(tabbed_pane))
  tabbed_pane.add_tab(tab_limits, build_limit_page(tabbed_pane))
  tabbed_pane.add_tab(tab_test, build_test_page(tabbed_pane))

  -- select "items" (not really needed, as that is the default)
  tabbed_pane.selected_tab_index = 1

  ui.net_view = {
    frame = frame,
    tabbed_pane = tabbed_pane,
    elems = elems,
    pinned = false,
    player = player,
  }

  M.update_items(player_index)
end

-- used when setting the active tab
local tab_idx_to_view_type = {
  "item",
  "fluid",
  "shortage",
  "limits",
  "test"
}

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

local function get_item_tooltip(name, count)
  local info = game.item_prototypes[name]
  if info == nil then
    return {
      "",
      name or "Unknown Item",
      ": ",
      count,
    }
  else
    return {
      "in_nv.item_sprite_btn_tooltip",
      info.localised_name,
      count,
    }
  end
end

local function get_fluid_tooltip(name, temp, count)
  local localised_name
  local info = game.fluid_prototypes[name]
  if info == nil then
    localised_name = name or "Unknown Fluid"
  else
    localised_name = info.localised_name
  end
  return {
    "in_nv.fluid_sprite_btn_tooltip",
    localised_name,
    string.format("%.0f", count),
    { "format-degrees-c", string.format("%.0f", temp) },
  }
end

local function get_item_shortage_tooltip(name, count)
  local info = game.item_prototypes[name]
  local localised_name
  if info == nil then
    localised_name = name or "Unknown Item"
  else
    localised_name = info.localised_name
  end
  return {
    "in_nv.item_shortage_sprite_btn_tooltip",
    localised_name,
    count,
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

  if net_view.view_type == "test" then
    M.render_tab_test(main_flow)
    return
  end

  if main_flow.vert_flow == nil then
    return
  end
  local item_flow = main_flow.vert_flow.item_flow
  item_flow.clear()

  if net_view.view_type == "limits" then
    M.render_tab_limits(main_flow)
    return
  end

  local view_type = net_view.view_type
  local is_item = view_type == "item"

  if is_item then
    item_flow.add({
      type = "sprite-button",
      sprite = "utility/slot_icon_resource_black",
--      style = "inventory_slot",
      tags = { event = UiConstants.NV_DEPOSIT_ITEM_SPRITE_BUTTON },
      tooltip = { "in_nv.deposit_item_sprite_btn_tooltip" },
    })
    M.pad_item_table_row(item_flow)
  end

  local items = M.get_list_of_items(view_type)
  for _, item in ipairs(items) do
    if type(item) ~= "table" then
      M.pad_item_table_row(item_flow)
    else
      local sprite_button = M.get_sprite_button_def(item, view_type)
      local sprite_button_inst = item_flow.add(sprite_button)
      sprite_button_inst.number = item.count
    end
  end
  M.pad_item_table_row(item_flow)
end

-- adds padding to the end of the current row
function M.pad_item_table_row(item_table, sprite)
  sprite = sprite or "inet_slot_empty_inset"
  local blank_def = {
    type = "sprite",
    sprite = sprite,
    ignored_by_interaction = true,
  }
  local column_count = item_table.column_count
  while #item_table.children % column_count > 0 do
    item_table.add(blank_def)
  end
end

function M.get_sprite_button_def(item, view_type)
  local tooltip
  local sprite_path
  local elem_type
  local tags
  if item.temp == nil then
    elem_type = "item"
    if view_type == "shortage" then
      tooltip = get_item_shortage_tooltip(item.item, item.count)
    else
      tooltip = get_item_tooltip(item.item, item.count)
      tags = { event = UiConstants.NV_ITEM_SPRITE_BUTTON, item = item.item }
    end
    if game.item_prototypes[item.item] == nil then
      sprite_path = nil
    else
      sprite_path = "item/" .. item.item
    end
  else
    elem_type = "fluid"
    tooltip = get_fluid_tooltip(item.item, item.temp, item.count)
    if game.fluid_prototypes[item.item] == nil then
      sprite_path = nil
    else
      sprite_path = "fluid/" .. item.item
    end
  end
  return {
    type = "sprite-button",
    elem_type = elem_type,
    sprite = sprite_path,
    tooltip = tooltip,
    tags = tags,
  }
end

function M.on_gui_click_item(event, element)
  --[[
  This handles a click on an item sprite in the item view.
  If the cursor has something in it, then the cursor content is dumped into the item network.
  If the cursor is empty then we grab something from the item network.
    left-click grabs one item.
    shift + left-click grabs one stack.
    ctrl + left-click grabs it all.
  ]]
  local player = game.players[event.player_index]
  if player == nil then
    return
  end
  local inv = player.get_main_inventory()
  if inv == nil then
    return
  end

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
        local n_moved = inv.insert({ name = item_name, count = n_transfer })
        if n_moved > 0 then
          GlobalState.set_item_count(item_name, network_count - n_moved)
          local count = GlobalState.get_item_count(item_name)
          element.number = count
          element.tooltip = get_item_tooltip(item_name, count)
        end
      end
    end
    return
  else
    -- There is a stack in the cursor. Deposit it.
    local cursor_stack = player.cursor_stack
    if not cursor_stack or not cursor_stack.valid_for_read then
      return
    end

    -- don't deposit tracked entities (can be unique)
    if cursor_stack.item_number ~= nil then
      game.print(string.format(
        "Unable to deposit %s because it might be a vehicle with items that will be lost.",
        cursor_stack.name))
      return
    end

    if event.button == defines.mouse_button_type.left then
      local item_name = cursor_stack.name

      -- move the stack to the item network
      GlobalState.increment_item_count(item_name, cursor_stack.count)
      cursor_stack.count = 0
      cursor_stack.clear()
      player.clear_cursor()

      -- if control is pressed, move all of that item to the network
      if event.control then
        local my_count = inv.get_item_count(item_name)
        if my_count > 0 then
          GlobalState.increment_item_count(item_name, my_count)
          inv.remove({name=item_name, count=my_count})
        end
      end
      M.update_items(event.player_index)
    end
  end
end

--------------------------------------------------------------------------------

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
  local item_table = main_flow.vert_flow.item_flow

  --[[
    Strategy: anything in the network appears in the list. If there is no limit, then show infinity.
    Any item/liquid that has a limit will have an icon.
    Show one row of blank boxes that can be clicked to bring up an item selection window with a limit bar on the bottom.
  ]]

  local items = M.get_list_of_items("limits")
  for _, item in ipairs(items) do
    if type(item) ~= "table" then
      M.pad_item_table_row(item_table)
    else
      local sprite_path = find_sprite_path(item.item)
      local sprite_button = {
        type = "sprite-button",
        sprite = sprite_path,
        style = "logistic_slot_button",
        tags = { event = UiConstants.NV_LIMIT_ITEM, item = item.item, temp=item.temp },
      }
      local tooltip
      if startswith(sprite_path, "item") then
        tooltip = get_item_tooltip(item.item, item.count)
      else
        tooltip = get_fluid_tooltip(item.item, item.temp or 10, item.count)
      end
      table.insert(tooltip, "\nLeft click to edit.\nRight click to remove/revert to defaults.")
      sprite_button.tooltip = tooltip
      local sprite_button_inst = item_table.add(sprite_button)
      sprite_button_inst.number = item.count
    end
  end
  M.pad_item_table_row(item_table)
end

--------------------------------------------------------------------------------

function M.render_tab_test(main_flow)

end

local function limit_compare_fluid(left, right)
  local left_order = game.fluid_prototypes[left.item].order
  local right_order = game.fluid_prototypes[right.item].order
  if left_order == left_order then
    return left.temp < right.temp
  end
  return left_order < right_order
end

local function limit_compare_item(left, right)
  local proto_left = game.item_prototypes[left.item]
  local proto_right = game.item_prototypes[right.item]

  if proto_left.group.order ~= proto_right.group.order then
    return proto_left.group.order < proto_right.group.order
  end
  if proto_left.subgroup.order ~= proto_right.subgroup.order then
    return proto_left.subgroup.order < proto_right.subgroup.order
  end
  return proto_left.order < proto_right.order
end

-- determines if the two items or fluids are in different subgroups and p2
-- should start a new line.
local function need_group_break(p1, p2)
  if p1 == nil or p2 == nil then
    return true
  end
  local p1_f = game.fluid_prototypes[p1]
  local p2_f = game.fluid_prototypes[p2]
  local p1_i = game.item_prototypes[p1]
  local p2_i = game.item_prototypes[p2]

  if ((p1_f == nil) ~= (p2_f == nil)) or ((p1_i == nil) ~= (p2_i == nil)) then
    -- need a break between fluid and items
    return true
  end
  if (p1_f ~= nil) or (p2_f ~= nil) then
    -- fluids
    return false
  end
  if p1_i == nil or p2_i == nil then
    return true
  end
  return (p1_i.group.name ~= p2_i.group.name) or (p1_i.subgroup.name ~= p2_i.subgroup.name)
end

local function items_sort_by_group_order(left, right)
  -- the deposit slot is always first
  if left.is_deposit_slot then
    return true
  end
  if right.is_deposit_slot then
    return false
  end

  -- fluids are next
  local left_f_proto = game.fluid_prototypes[left.item]
  local right_f_proto = game.fluid_prototypes[right.item]
  if left_f_proto ~= nil then
    if right_f_proto ~= nil then
      return limit_compare_fluid(left, right)
    end
    return true
  end

  -- items are last
  local left_i_proto = game.item_prototypes[left.item]
  local right_i_proto = game.item_prototypes[right.item]
  if left_i_proto ~= nil and right_i_proto ~= nil then
      return limit_compare_item(left, right)
  end

  -- anything else is randomly thrown at the end
  return left_i_proto ~= nil
end

-- sort the list and insert a string between items that are in different subgroups
local function items_list_split_by_group(items)
  table.sort(items, items_sort_by_group_order)
  local out_items = {}
  local last_item_name
  for _, item in ipairs(items) do
    if last_item_name ~= nil and need_group_break(last_item_name, item.item) then
      table.insert(out_items, "break")
    end
    table.insert(out_items, item)
    last_item_name = item.item
  end
  return out_items
end

local function items_list_sort(left, right)
  if left.is_deposit_slot then
    return true
  end
  if right.is_deposit_slot then
    return false
  end
  return left.count > right.count
end

function M.get_list_of_items(view_type)
  local items = {}

  local function add_item(item)
    if game.item_prototypes[item.item] ~= nil or game.fluid_prototypes[item.item] ~= nil then
      table.insert(items, item)
    end
  end

  if view_type == "item" then
    local items_to_display = GlobalState.get_items()
    for item_name, item_count in pairs(items_to_display) do
      if item_count > 0 then
        add_item({ item = item_name, count = item_count })
      end
    end
    -- sort and split by subgroup/order
    return items_list_split_by_group(items)

  elseif view_type == "fluid" then
    local fluids_to_display = GlobalState.get_fluids()
    for fluid_name, fluid_temps in pairs(fluids_to_display) do
      for temp, count in pairs(fluid_temps) do
        add_item({ item = fluid_name, count = count, temp = temp })
      end
    end
    -- sort by order, then temperature
    table.sort(items, limit_compare_fluid)
    return items

  elseif view_type == "shortage" then
    -- add item shortages
    local missing = GlobalState.missing_item_filter()
    for item_name, count in pairs(missing) do
      -- sometime shortages can have invalid item names.
      if game.item_prototypes[item_name] ~= nil then
        table.insert(items, { item = item_name, count = count })
      end
    end

    -- add fluid shortages
    missing = GlobalState.missing_fluid_filter()
    for fluid_key, count in pairs(missing) do
      local fluid_name, temp = GlobalState.fluid_temp_key_decode(fluid_key)
      table.insert(items, { item = fluid_name, count = count, temp = temp })
    end
    -- sort so that the largest shortages are first
    table.sort(items, items_list_sort)
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
    local last_item
    for _, ent in ipairs(items) do
      if need_group_break(last_item, ent.item) then
        table.insert(fluids, "break")
      end
      table.insert(fluids, ent)
      last_item = ent.item
    end
    return fluids
  end

  return items
end

function M.destroy(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  if ui.net_view ~= nil then
    ui.net_view.frame.destroy()
    ui.net_view = nil
  end
end

function M.on_gui_closed(event)
  local ui = GlobalState.get_ui_state(event.player_index)
  if ui.net_view ~= nil then
    if ui.net_view.pinned then
      return
    end
  end
  M.destroy(event.player_index)
end

-- close button pressed
function M.on_gui_close(event)
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
      game.print(string.format("limit_set_edit_item: item [%s] group [%s] subgroup [%s] limit=%s",
        item_name, prot.group.name, prot.subgroup.name, item_limit))
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

--- @param self  => GlobalState.get_ui_state(player_index).net_view
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
  local ui = GlobalState.get_ui_state(event.player_index)
  if ui.net_view ~= nil then
    M.toggle_pinned(ui.net_view)
  end
end

return M
