--[[
Test code to put up a Entity GUI next to serviced items.
]]
local GlobalState = require "src.GlobalState"
local GUIDispatcher = require 'src.GUIDispatcher'
local GUICommon = require 'src.GUICommon'
local service_furnace = require 'src.service_furnace'
local GUIComponentSliderInput = require "src.GUIComponentSliderInput"

local M = {}

local EntityTypeGUIAnchors = {
  ["assembling-machine"] = defines.relative_gui_type.assembling_machine_gui,
  ["car"] = defines.relative_gui_type.car_gui,
  ["logistic-container"] = defines.relative_gui_type.container_gui,
  ["container"] = defines.relative_gui_type.container_gui,
  ["furnace"] = defines.relative_gui_type.furnace_gui,
  ["lab"] = defines.relative_gui_type.lab_gui,
  ["mining-drill"] = defines.relative_gui_type.mining_drill_gui,
  ["boiler"] = defines.relative_gui_type.entity_with_energy_source_gui,
  ["burner-generator"] = defines.relative_gui_type.entity_with_energy_source_gui,
  ["artillery-turret"] = defines.relative_gui_type.container_gui,
  ["ammo-turret"] = defines.relative_gui_type.container_gui,
  ["reactor"] = defines.relative_gui_type.reactor_gui,
  ["storage-tank"] = defines.relative_gui_type.storage_tank_gui,
  ["rocket-silo"] = defines.relative_gui_type.rocket_silo_gui,
  ["spider-vehicle"] = defines.relative_gui_type.spider_vehicle_gui,
  ["constant-combinator"] = defines.relative_gui_type.constant_combinator_gui,
}

function M.initialize()
  if global.entity_panel_location == nil then
    global.entity_panel_location = {}
  end
  if global.entity_panel_pending_relocations == nil then
    global.entity_panel_pending_relocations = {}
  end
end

M.GUI_ENTITY_PANEL ="cin-entity-panel"
M.GUI_CLOSE_EVENT = "cin-entity-panel-close"
local DISABLED_CHECKED_EVENT = "cin-entity-panel-disable"
local PRIORITISE_CHECKED_EVENT = "cin-entity-panel-prioritise"
local CONDITION_ITEM_EVENT = "cin-entity-panel-condition-item"
M.OPERATIONS = { "≥", "≤" }
local CONDITION_OP_EVENT = "cin-entity-panel-condition-op"
local CONDITION_VALUE_BUTTON_EVENT = "cin-entity-panel-condition-button"
local CONDITION_VALUE_CHANGED_EVENT = "cin-entity-panel-condition-value-changed"
local CONDITION_SURFACE_CHANGED_EVENT = "cin-entity-panel-condition-surface-changed"
local CONDITION_SURFACE_RESET_EVENT = "cin-entity-panel-condition-surface-reset"
local FURNACE_RECIPE_EVENT = "cin-entity-panel-furnace-recipe"
local RETURN_EXCESS_CHECKED_EVENT = "cin-entity-panel-return-excess"
local SHOW_PRIORITY_GUI_EVENT = "cin-entity-panel-show-priority-gui"

-- get some sort of unique key for the entity (generic)
local function get_location_key(player, entity_name)
  return ("%d;%s;%s;%s"):format(
    player.index,
    player.opened.get_mod(),
    entity_name,
    player.opened.name
  )
end

-------------------------------------------------------------------------------

--[[
Look for and close the GUI_ENTITY_PANEL.
If it was under player.gui.screen, then return the window location.
]]
function M.gui_close(player)
  local last_position
  local window = player.gui.relative[M.GUI_ENTITY_PANEL]
  if window then
    window.destroy()
  end

  window = player.gui.screen[M.GUI_ENTITY_PANEL]
  if window then
    last_position = window.location
    window.destroy()
  end
  return last_position
end

local function add_panel_frame(parent, caption, tooltip)
  parent.add({
    type = "line",
    style = "control_behavior_window_line"
  })
  local frame = parent.add({
    type = "frame",
    style = "invisible_frame",
    direction = "vertical"
  })
  local label = frame.add({
    type = "label",
    style = "heading_2_label",
    caption = caption,
    tooltip = tooltip
  })
  label.style.padding = { 4, 0, 4, 0 }
  return frame
end

--[[
Build the GUI content.
]]
local function add_gui_content(window, entity, info)
  local data_id = entity.unit_number
  local config = info.config or {}

  print(serpent.block(info))

  local frame = window.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })

  -- Disabled
  frame.add({
    type = "checkbox",
    caption = "Service Disabled [img=info]",
    tooltip = "Disable all servicing of this entity",
    state = (config.disabled == true),
    tags = { id = data_id, event = DISABLED_CHECKED_EVENT }
  })

  -- Prioritise
  frame.add({
    type = "checkbox",
    caption = "Prioritise [img=info]",
    tooltip = "Allow consumption of reserved resources",
    state = (config.use_reserved == true),
    tags = { id = data_id, event = PRIORITISE_CHECKED_EVENT }
  })
  frame.add({
    type = "line",
    style = "control_behavior_window_line"
  })

  -- Condition
  if not config.condition then
    config.condition = {}
  end
  local condition = config.condition
  local condition_value = config.condition_value or 0

  local condition_frame = frame.add({
    type = "frame",
    name = "condition_frame",
    style = "invisible_frame_with_title",
    caption = { "gui-control-behavior-modes-guis.enabled-condition" },
    direction = "vertical"
  })
  local condition_controls_flow = condition_frame.add({
    type = "flow",
    name = "condition_controls_flow",
    direction = "horizontal"
  })
  condition_controls_flow.style.vertical_align = "center"

  local fluid_name = "" -- Storage.unpack_fluid_item_name(condition.item or "")
  condition_controls_flow.add({
    type = "choose-elem-button",
    elem_type = "signal",
    style = "slot_button_in_shallow_frame",
    signal = {
      type = fluid_name and "fluid" or "item",
      name = fluid_name or condition.item
    },
    tags = { id = data_id, event = CONDITION_ITEM_EVENT }
  })
  condition_controls_flow.add({
    type = "drop-down",
    items = M.OPERATIONS,
    selected_index = config.condition_op or 1,
    style = "circuit_condition_comparator_dropdown",
    tags = { id = data_id, event = CONDITION_OP_EVENT }
  })
  local condition_value_btn = condition_controls_flow.add({
    type = "button",
    name = "condition_value",
    style = "slot_button_in_shallow_frame",
    caption = condition_value .. "%",
    tags = { event = CONDITION_VALUE_BUTTON_EVENT }
  })
  condition_value_btn.style.font_color = { 1, 1, 1 }

  local condition_slider_flow = condition_frame.add({
    type = "flow",
    name = "slider_flow",
    style = "player_input_horizontal_flow",
  })
  condition_slider_flow.style.top_padding = 4
  condition_slider_flow.visible = false
  GUIComponentSliderInput.create(
    condition_slider_flow,
    {
      value = condition_value,
      maximum_value = 100,
      style = "slider",
      tags = { id = data_id, event = { [CONDITION_VALUE_CHANGED_EVENT] = true } }
    },
    {
      allow_negative = false,
      style = "very_short_number_textfield",
      tags = { id = data_id, event = { [CONDITION_VALUE_CHANGED_EVENT] = true } }
    }
  )
  condition_slider_flow.slider.style.width = 100

  condition_slider_flow.add({
    type = "label",
    caption = "%",
  })
--[[
  local surface_names = Util.table_keys(game.surfaces)
  local current_surface = condition.surface or entity.surface.name
  local current_surface_i = flib_table.find(surface_names, current_surface)
  if current_surface_i == nil then
    table.insert(surface_names, ("%s%s (not found)%s"):format(R.COLOUR_RED, current_surface, R.COLOUR_END))
    current_surface_i = #surface_names
  end
  if table_size(surface_names) > 1 then
    local condition_surface_flow = condition_frame.add({
      type = "flow",
      direction = "horizontal"
    })
    condition_surface_flow.style.vertical_align = "center"

    condition_surface_flow.add({
      type = "label",
      style = "heading_2_label",
      caption = "Storage source [img=info]",
      tooltip = "The surface of the storage to use when checking the condition, and reading signals (for [entity=arr-combinator] Auto Resource Combinators)"
    })

    local button = condition_surface_flow.add({
      type = "sprite-button",
      resize_to_sprite = false,
      sprite = "utility/reset_white",
      tooltip = "Click to reset to current surface",
      tags = { id = data_id, event = CONDITION_SURFACE_RESET_EVENT }
    })
    button.style.size = { 24, 24 }

    condition_frame.add({
      type = "drop-down",
      name = "condition_surface",
      items = surface_names,
      selected_index = current_surface_i,
      tags = { id = data_id, event = CONDITION_SURFACE_CHANGED_EVENT }
    })
  end

  if entity.name == "arr-logistic-requester-chest" then
    local sub_frame = add_panel_frame(frame, "Requester Chest")
    frame.add({
      type = "checkbox",
      caption = "Return excess items [img=info]",
      tooltip = "Return items that are not requested or are above the requested amount",
      state = (data.return_excess == true),
      tags = { id = data_id, event = RETURN_EXCESS_CHECKED_EVENT }
    })
  end
]]
  if entity.type == "furnace" then
    local sub_frame = add_panel_frame(
      frame,
      { "", { "description.recipe" }, " [img=info]" },
      "The new recipe will be applied on the next production cycle, when the productivity bar is empty."
    )
    local current_recipe = service_furnace.get_recipe_name(info)
    local filters = {}
    for category, _ in pairs(entity.prototype.crafting_categories) do
      table.insert(filters, { filter = "category", category = category })
    end
    --FIXME: would be great to look up if the recipe has been researched
    sub_frame.add({
      type = "choose-elem-button",
      elem_type = "recipe",
      style = "slot_button_in_shallow_frame",
      recipe = current_recipe,
      elem_filters = filters,
      tags = { id = data_id, event = FURNACE_RECIPE_EVENT }
    })
  end
--[[
  local priority_sets = ItemPriorityManager.get_priority_sets_for_entity(entity)
  -- { [group] = { set1_key, set2_key, ... } }
  local related_priority_set_keys = {}
  for set_key, priority_set in pairs(priority_sets) do
    if priority_set.group then
      local sets = related_priority_set_keys[priority_set.group] or {}
      table.insert(sets, set_key)
      related_priority_set_keys[priority_set.group] = sets
    end
  end
  if table_size(related_priority_set_keys) > 0 then
    local sub_frame = add_panel_frame(
      frame,
      "Item Priority [img=info]",
      {
        "", ("Effects every [entity=%s] "):format(entity.name), entity.localised_name,
        "\nItems are used from left to right.\n",
        R.HINT, { "control-keys.mouse-button-1" }, R.HINT_END, " to set item quantity.",
      }
    )
    sub_frame.style.vertically_stretchable = false
    local inner_flow = sub_frame.add({
      type = "flow",
      direction = "vertical"
    })
    inner_flow.style.left_margin = 4
    inner_flow.style.vertical_spacing = 0
    for group, set_keys in pairs(related_priority_set_keys) do
      local label_flow = inner_flow.add({
        type = "flow",
        direction = "horizontal"
      })
      label_flow.style.vertical_align = "center"

      local label = label_flow.add({
        type = "label",
        style = "heading_2_label",
        caption = group,
      })
      label.style.bottom_padding = 0

      local button = label_flow.add({
        type = "sprite-button",
        resize_to_sprite = false,
        sprite = "arr-logo",
        tooltip = "Click to show in the full priority list window",
        tags = {
          event = SHOW_PRIORITY_GUI_EVENT,
          group = group,
          entity = entity.name,
        }
      })
      button.style.size = { 24, 24 }

      for _, set_key in ipairs(set_keys) do
        local flow = inner_flow.add({
          type = "flow",
        })
        GUIComponentItemPrioritySet.create(flow, priority_sets, set_key, 6)
      end
    end
  end
]]
end


local function my_on_gui_opened(event)
  if global.test_gui ~= nil then
    global.test_gui.destroy()
    global.test_gui = nil
  end
  local player = game.players[event.player_index]
  if player == nil then
    print(string.format("on_gui_open: typ=%s tis nil", event.gui_type))
    return
  end
  if player.gui == nil then
    print(string.format("on_gui_open: typ=%s gui is nil", event.gui_type))
    return
  end
  local entity = event.entity
  if event.gui_type == defines.gui_type.entity and entity ~= nil and entity.type == "furnace" then
    print(string.format("on_gui_open: type=%s name=%s unum=%s", event.gui_type, entity.name, entity.unit_number))
    global.test_gui = player.gui.relative.add({
      type = "frame",
      style = "inset_frame_container_frame",
      anchor = {
        gui      = defines.relative_gui_type.furnace_gui,
        position = defines.relative_gui_position.right,
      },
    })
    local vflow = global.test_gui.add({
      type = "flow",
      direction = "vertical",
    })
    local hflow = vflow.add({
      type = "flow",
      direction = "horizontal",
    })

    hflow.add({
      type = "label",
      caption = "Pick The Recipe",
      style = "frame_title",
    })
    vflow.add({
      type = "sprite-button",
      sprite = "item/locomotive",
    })
    -- the category should be taken from the furnace categories
    local ef = {}
    local mode
    for cc, _ in pairs(entity.prototype.crafting_categories) do
      table.insert(ef, { mode = mode, filter = "category", category = cc })
      mode = "or"
    end
    table.insert(ef, { mode = "and", filter="has-product-item" })
    table.insert(ef, { mode = "and", filter="hidden", invert=true })
    vflow.add({
      type = "choose-elem-button",
      elem_type = "recipe",
      elem_filters = ef,
    })
  end
end

local function on_gui_opened(event, tags, player)
  local last_position = M.gui_close(player)
  local entity = event.entity
  if entity == nil or not entity.valid or entity.unit_number == nil then
    return
  end
  local info = GlobalState.entity_info_get(entity.unit_number)
  if info == nil then
    -- see if this is something we handle
    if GlobalState.get_service_type_for_entity(entity.name) == nil then
      return
    end
    info = GlobalState.entity_info_add(entity)
  end

  -- if .opened is a custom UI, then open on screen instead because we can't anchor
  if player.opened and player.opened.object_name == "LuaGuiElement" then
    local parent = player.gui.screen
    local window = parent.add({
      type = "frame",
      name = M.GUI_ENTITY_PANEL,
      direction = "vertical",
      style = "inner_frame_in_outer_frame",
      tags = { entity_name = entity.name, unit_number = entity.unit_number }
    })

    GUICommon.create_header(window, "Cheat Network", M.GUI_CLOSE_EVENT)
    -- use the location from the previous time a similar UI was opened
    -- this might be incorrect, but should be corrected on the next tick
    local location_key = get_location_key(player, entity.name)
    last_position = global.entity_panel_location[location_key] or last_position
    local res = player.display_resolution
    if last_position and last_position.x + 100 < res.width and last_position.y + 100 < res.height then
      window.location = last_position
    else
      window.force_auto_center()
    end
    -- the position of the parent GUI will only be known on the next tick
    -- so set a flag for on_tick to reposition us later
    global.entity_panel_pending_relocations[player.index] = {
      player = player,
      tick = game.tick + 1
    }
    add_gui_content(window, entity, info)
    return
  end

  local anchor = EntityTypeGUIAnchors[entity.type]
  if not anchor then
    log(("FIXME: don't know how to anchor to entity GUI name=%s type=%s"):format(entity.name, entity.type))
    return
  end

  local relative = player.gui.relative
  local window = relative[GUICommon.GUI_ENTITY_PANEL]
  window = relative.add({
    type = "frame",
    name = GUICommon.GUI_ENTITY_PANEL,
    direction = "vertical",
    style = "inner_frame_in_outer_frame",
    anchor = {
      position = defines.relative_gui_position.right,
      gui = anchor,
    },
    caption = "Cheat Network",
    tags = { entity_id = entity.unit_number }
  })
  add_gui_content(window, entity, info)
end

local function on_gui_closed(event, tags, player)
  M.gui_close(player)
end

local function on_disabled_checked(event, tags, player)
  GlobalState.entity_info_config_update(tags.id, { disabled = event.element.state })
end

local function on_prioritise_checked(event, tags, player)
  GlobalState.entity_info_config_update(tags.id, { use_reserved = event.element.state })
end

local function on_condition_item_changed(event, tags, player)
  --[[
  local signal = event.element.elem_value
  local storage_key = signal and (signal.type == "fluid" and Storage.get_fluid_storage_key(signal.name) or signal.name)
  if signal and signal.type == "virtual" then
    event.element.elem_value = nil
    return
  end
  global.entity_data[tags.id].condition.item = storage_key
  GlobalState.entity_info_config_update(tags.id, { condition_item = storage_key })
  ]]
end

local function on_condition_op_changed(event, tags, player)
  GlobalState.entity_info_config_update(tags.id, { condition_op = event.element.selected_index })
end

local function on_furnace_recipe_changed(event, tags, player)
  local new_recipe_name = event.element.elem_value
  local info = GlobalState.entity_info_get(tags.id)
  if not info then
    return
  end
  --local entity = global.entities[tags.id]
  -- go back to the current recipe
  if not new_recipe_name then
    --local recipe = info.config.recipe -- FurnaceRecipeManager.get_recipe(entity)
    event.element.elem_value = service_furnace.get_recipe_name(info)
    return
  end

  service_furnace.set_recipe_name(info, new_recipe_name)
  --FurnaceRecipeManager.set_recipe(entity, new_recipe_name)
end

GUIDispatcher.register(defines.events.on_gui_elem_changed, FURNACE_RECIPE_EVENT, on_furnace_recipe_changed)

GUIDispatcher.register(defines.events.on_gui_opened, nil, on_gui_opened)
GUIDispatcher.register(defines.events.on_gui_closed, nil, on_gui_closed)

GUIDispatcher.register(defines.events.on_gui_checked_state_changed, DISABLED_CHECKED_EVENT, on_disabled_checked)
GUIDispatcher.register(defines.events.on_gui_checked_state_changed, PRIORITISE_CHECKED_EVENT, on_prioritise_checked)

GUIDispatcher.register(defines.events.on_gui_elem_changed, CONDITION_ITEM_EVENT, on_condition_item_changed)
GUIDispatcher.register(defines.events.on_gui_selection_state_changed, CONDITION_OP_EVENT, on_condition_op_changed)
GUIDispatcher.register(defines.events.on_gui_click, CONDITION_VALUE_BUTTON_EVENT, on_condition_value_clicked)
GUIDispatcher.register(defines.events.on_gui_value_changed, CONDITION_VALUE_CHANGED_EVENT, on_condition_value_changed)
GUIDispatcher.register(defines.events.on_gui_text_changed, CONDITION_VALUE_CHANGED_EVENT, on_condition_value_changed)
GUIDispatcher.register(defines.events.on_gui_confirmed, CONDITION_VALUE_CHANGED_EVENT, on_condition_value_confirmed)
GUIDispatcher.register(defines.events.on_gui_selection_state_changed, CONDITION_SURFACE_CHANGED_EVENT, on_condition_surface_changed)
GUIDispatcher.register(defines.events.on_gui_click, CONDITION_SURFACE_RESET_EVENT, on_condition_surface_reset_clicked)

GUIDispatcher.register(defines.events.on_gui_elem_changed, FURNACE_RECIPE_EVENT, on_furnace_recipe_changed)

GUIDispatcher.register(defines.events.on_gui_checked_state_changed, RETURN_EXCESS_CHECKED_EVENT, on_return_excess_checked)

GUIDispatcher.register(defines.events.on_gui_click, SHOW_PRIORITY_GUI_EVENT, on_show_priority_gui)

return M
