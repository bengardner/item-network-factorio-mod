--[[
Allows configuration of allowable fuels.
]]
local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local GUICommon = require "src.GUICommon"
local GUIDispatcher = require "src.GUIDispatcher"
local R = require "src.RichText"
local Gui = require('__stdlib__/stdlib/event/gui')
local item_utils = require "src.item_utils"
local clog = require("src.log_console").log

-- M is the module that supplies 'create()'
local M = {}

local BUTTON_CLICK_EVENT = "cin-component-priority-set-button"
local SLIDER_INPUT_EVENT = "cin-component-priority-set-slider"

local NetFuels = {}


local NetFuels__metatable = { __index = NetFuels }
script.register_metatable("NetFuels", NetFuels__metatable)

local function gui_get(player_index)
  return GlobalState.get_ui_state(player_index).UiNetworkFuels
end

local function gui_set(player_index, value)
  GlobalState.get_ui_state(player_index).UiNetworkFuels = value
end

function M.create(parent, player, show_title)
  local self = {
    player = player,
    elems = {},
    use_group = false,
  }

  -- set index so we can call self:refresh() or M.refresh(self)
  -- FIXME: need to restore mettables
  setmetatable(self, NetFuels__metatable)

  local vert_flow = parent.add({
    type = "flow",
    direction = "vertical",
  })
  self.frame = vert_flow

  local inv_frame = vert_flow.add({
    type = "frame",
    style = "character_inventory_frame",
    --style = "inventory_frame",
  })
  local scroll_pane = inv_frame.add({
    type = "scroll-pane",
    style = "character_inventory_scroll_pane",
    --style = "entity_inventory_scroll_pane",
  }) -- 424, 728 or 400,712
  scroll_pane.style.width = 424

  --[[
  local hdr = scroll_pane.add({
    type = "flow",
    direction = "horizontal",
  })
  hdr.style.size = { 400, 28 }

  self.elems.title = hdr.add({
    type = "label",
    caption = "Network Fuels",
    style = "inventory_label",
  })
  local hdr_spacer = hdr.add({ type = "empty-widget" })
  hdr_spacer.style.horizontally_stretchable = true
  ]]
  local item_table = scroll_pane.add({
    type = "table",
    name = "item_table",
    style = "slot_table",
    column_count = 3
  })
  item_table.style.horizontal_spacing = 12
  self.elems.item_table = item_table

  gui_set(player.index, self)

  -- populate the table
  NetFuels.refresh(self)

  return self
end

function NetFuels.destroy(self)
  if self.frame ~= nil then
    self.frame.destroy() -- destroy the GUI
    self.frame = nil
  end
  gui_set(self.player.index, nil)
end

local function get_list_of_items()
  local fuel_items = {}
  local fuel_tab = GlobalState.get_fuel_table()

  for name, prot in pairs(game.entity_prototypes) do
    local fct = prot.burner_prototype
    if fct ~= nil then
      local fuel_rec = {}
      for _, fuel in ipairs(fuel_tab) do
        if fct.fuel_categories[fuel.cat] ~= nil then
          table.insert(fuel_rec, fuel)
        end
      end
      if #fuel_rec > 0 then
        fuel_items[name] = fuel_rec
      end
    end
  end

  --[[
  for name, ii in pairs(fuel_items) do
    print(string.format("fuel for %s [%s]", name, #ii))
    for _, xx in ipairs(ii) do
      print(string.format("  - %s", serpent.line(xx)))
    end
  end
  ]]

  return fuel_items
end

-- TODO: move to GlobalState so it can be viewed via gvv?
local fuel_filters = {}

local function get_fuel_filter_for_entity(name)
  -- the filter never changes, so cache it
  local filt = fuel_filters[name]
  if filt ~= nil then
    return filt
  end

  filt = {}
  local bprot = game.entity_prototypes[name].burner_prototype
  if bprot ~= nil then
    for cat, _ in pairs(bprot.fuel_categories) do
      local nv = { filter = "fuel-category", ["fuel-category"] = cat }
      if #filt > 0 then
        nv.mode = "or"
      end
      table.insert(filt, nv)
    end
  end
  fuel_filters[name] = filt
  return filt
end

--[[
  The table has three columns.
  1. the item to service.
  2. the preferred fuel
  3. row of forbidden fuels.
]]
function NetFuels:refresh()
  local item_table = self.elems.item_table
  item_table.clear()

  -- first row
  item_table.add({
    type = "label",
    caption = "Entity",
  })
  item_table.add({
    type = "label",
    caption = "Copy",
  })
  item_table.add({
    type = "label",
    caption = "Fuels",
  })

  -- add the items
  local items = get_list_of_items()
  for name, fuel_list in pairs(items) do
    -- make sure it is something we service
    if global.name_service_map[name] ~= nil then
      local cfg = GlobalState.fuel_config_get(name)

      -- put the entity button down
      local ent_elem = item_table.add({
          type = "choose-elem-button",
          elem_type = "entity",
      })
      ent_elem.elem_value = name
      ent_elem.locked = true

      item_table.add({
        type = "label",
        caption = "*",
      })
      --[[
      -- add the preferred fuel selector
      local f_elem = item_table.add({
        type = "choose-elem-button",
        elem_type = "item",
        name=string.format("%s:%s", UiConstants.NETFUEL_SELECT_ITEM, name),
        tags = { name = name },
      })
      if cfg.preferred ~= nil then
        f_elem.elem_value = cfg.preferred
      end
      f_elem.elem_filters = get_fuel_filter_for_entity(name)
      ]]

      -- add the forbidden fuel list
      local hflow = item_table.add({ type="flow", direction = "horizontal" })
      local cnt = 1
      for _, fuel in ipairs(fuel_list) do
        local style = nil
        if cfg[fuel.name] == true then
          style = "red_slot_button"
          -- style = "yellow_slot_button"
        end
        local fuel_elem = hflow.add({
          name = string.format("%s:%s", UiConstants.NETFUEL_BLOCK_ITEM, cnt),
          type = "choose-elem-button",
          style = style,
          elem_type = "item",
          tags = { name = name, fuel = fuel.name },
        })
        fuel_elem.elem_value = fuel.name
        fuel_elem.locked = true

        local count = 1
        if cfg[fuel.name] == true  then
          count = 0
        end
        GUICommon.create_item_button(
          hflow,
          fuel.name,
          {
            number = count > 0 and count or 0,
            name = fuel.name,
            style = count > 0 and "logistic_slot_button" or "red_logistic_slot_button",
            elem_tooltip = true,
            tooltip = table.concat({
              R.HINT, "Right-click", R.HINT_END, " to blacklist.\n",
              R.HINT, "Shift + Left-click", R.HINT_END, " to move forwards.\n",
              R.HINT, "Shift + Right-click", R.HINT_END, " to move backwards.\n",
              R.HINT, "Control + Left-click", R.HINT_END, " to move to front.\n",
              R.HINT, "Control + Right-click", R.HINT_END, " to move to back.",
            }),
            tags = { event = BUTTON_CLICK_EVENT },
          }
        )

        --[[
        hflow.add({
          name = fuel,
          type = "sprite-button",
          style = "logistic_slot_button",
          sprite = "item/" .. fuel,
          elem_tooltip = { type = "item", name = fuel },
        })
        ]]

        cnt = cnt + 1
      end
    end
  end
end

------------------------------------------------------------------------------
-- Event handling below

-- the item selection change. refresh the current limit text box
local function on_fuel_item_elem_changed(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    local name = event.element.tags.name
    if name ~= nil then
      local cfg = GlobalState.fuel_config_get(name)
      local fuel = event.element.elem_value
      cfg.preferred = fuel
      if fuel ~= nil then
        cfg[fuel] = nil
      end
      GlobalState.fuel_config_set(name, cfg)
      NetFuels.refresh(self)
    end
  end
end

-- toggles whether a fuel is blocked
local function on_fuel_blocked(event)
  local self = gui_get(event.player_index)
  if self ~= nil then
    local tags = event.element.tags
    local name = tags.name
    local fuel = tags.fuel
    if name ~= nil and fuel ~= nil then
      local cfg = GlobalState.fuel_config_get(name)
      -- toggle whether the fuel is blocked
      if cfg[fuel] ~= true then
        cfg[fuel] = true
      else
        cfg[fuel] = nil
      end
      GlobalState.fuel_config_set(name, cfg)
      NetFuels.refresh(self)
    end
  end
end

local function on_button_click(event, tags, player)
  log(("%s %s"):format(event.element.name, serpent.line(event)))
  if true then
    return
  end
  local click_str = GUICommon.get_click_str(event)
  local table_elem = event.element.parent
  local domain_key = table_elem.tags.domain
  local priority_sets = ItemPriorityManager.get_priority_sets_for_domain(domain_key)
  local set_key = table_elem.tags.key
  local priority_set = priority_sets[set_key]
  local clicked_item_name = event.element.name
  local clicked_item_index = flib_table.find(priority_set.item_order, clicked_item_name)
  local clicked_item_count = priority_set.item_counts[clicked_item_name]
  local updated = false

  if click_str == "left" then
    local slider_flow = table_elem.parent.parent.slider_flow
    local selected_item = slider_flow.tags.item
    if selected_item == clicked_item_name then
      slider_flow.tags = {}
    elseif clicked_item_count > 0 then
      slider_flow.tags = {
        domain = domain_key,
        key = set_key,
        item = clicked_item_name,
      }
    end
    updated = true
  end

  if click_str == "right" then
    -- toggle blacklist
    priority_set.item_counts[clicked_item_name] = clicked_item_count == 0 and 1 or -clicked_item_count
    updated = true
  elseif click_str == "control-left" then
    -- move to front
    updated = array_move_item(priority_set.item_order, clicked_item_index, 1)
  elseif click_str == "control-right" then
    -- move to back
    updated = array_move_item(priority_set.item_order, clicked_item_index, -1)
  elseif click_str == "shift-left" then
    -- swap left
    updated = table_swap(priority_set.item_order, clicked_item_index, clicked_item_index - 1)
  elseif click_str == "shift-right" then
    -- swap right
    updated = table_swap(priority_set.item_order, clicked_item_index, clicked_item_index + 1)
  end

  if updated then
    update_components(table_elem, priority_sets, true)
  end
end

Gui.on_elem_changed(UiConstants.NETFUEL_SELECT_ITEM, on_fuel_item_elem_changed)
Gui.on_click(UiConstants.NETFUEL_BLOCK_ITEM, on_fuel_blocked)

GUIDispatcher.register(defines.events.on_gui_click, BUTTON_CLICK_EVENT, on_button_click)

return M
