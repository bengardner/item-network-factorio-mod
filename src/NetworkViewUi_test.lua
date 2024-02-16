local GlobalState = require "src.GlobalState"
local UiConstants = require "src.UiConstants"
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local UiCharacterInventory = require "src.UiCharacterInventory"
local UiNetworkItems = require "src.UiNetworkItems"
local UiChestInventory = require "src.UiChestInventory"
local clog = require("src.log_console").log
local auto_player_request = require'src.auto_player_request'
local constants           = require 'src.constants'

local M = {}

M.container_width = 1424
M.container_height = 836

M.super_debug = false

function M.get_gui(player_index)
  return GlobalState.get_ui_state(player_index).test_view
end

--  Destroy the GUI for a player
function M.destroy_gui(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local self = ui.test_view
  if self ~= nil then
    -- break the link to prevent future events
    ui.test_view = nil

    -- call destructor on any child classes
    for _, ch in pairs(self.children) do
      if type(ch.destroy) == "function" then
        ch.destroy(ch)
      end
    end

    local player = self.player
    if player.opened == self.elems.main_window then
      player.opened = nil
    end

    -- destroy the UI
    self.elems.main_window.destroy()
  end
end

--  Create and show the GUI for a player
function M.create_gui(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local old_self = ui.test_view
  if old_self ~= nil then
    -- hotkey toggles the GUI
    M.destroy_gui(player_index)
    return
  end

  local player = game.get_player(player_index)
  if player == nil then
    return
  end

  -- important elements are stored here
  --   main_window
  --   ??
  local elems = {}

  -- create the main window
  elems.main_window = player.gui.screen.add({
    type = "frame",
    name = UiConstants.TV_MAIN_FRAME,
    style = "inset_frame_container_frame",
  })
  elems.main_window.auto_center = true
  elems.main_window.style.horizontally_stretchable = true
  elems.main_window.style.vertically_stretchable = true

  local vert_flow = elems.main_window.add({
    type = "flow",
    direction = "vertical",
  })
  vert_flow.style.horizontally_stretchable = true
  vert_flow.style.vertically_stretchable = true

  -- add the header/toolbar
  local header_flow = vert_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  header_flow.drag_target = elems.main_window

  header_flow.add {
    type = "label",
    caption = "Item Network Test Window",
    style = "frame_title",
    ignored_by_interaction = true,
  }

  local header_drag = header_flow.add {
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true,
  }
  header_drag.style.horizontally_stretchable = true
  header_drag.style.vertically_stretchable = true

  header_flow.add {
    name = UiConstants.TV_REFRESH_BTN,
    type = "sprite-button",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = { "gui.refresh" },
  }

  elems.close_button = header_flow.add {
    name = UiConstants.TV_CLOSE_BTN,
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
  }

  elems.pin_button = header_flow.add {
    name = UiConstants.TV_PIN_BTN,
    type = "sprite-button",
    sprite = "flib_pin_white",
    hovered_sprite = "flib_pin_black",
    clicked_sprite = "flib_pin_black",
    style = "frame_action_button",
  }

  -- add shared body area
  local body_flow = vert_flow.add({
    type = "flow",
    direction = "horizontal",
  })

  -- dummy flow to be the parent of the character inventory
  local left_pane = body_flow.add({
    type = "flow",
  })
  -- testing if I actually need this size or if it will adjust
  --left_pane.style.size = { 464, 828 }

  local mid_pane = body_flow.add({
    type = "flow",
    --type = "frame",
    --style = "frame_without_left_and_right_side",
  })
  --mid_pane.style.size = { 467, 828 }


  local right_pane = body_flow.add({
    type = "flow",
  })
  --right_pane.style.size = { 476, 828 }

  local self = {
    elems = elems,
    pinned = false,
    player = player,
    children = {},
  }
  ui.test_view = self
  player.opened = elems.main_window

  self.children.character_inventory = UiCharacterInventory.create(left_pane, player)
  self.children.network_items = UiNetworkItems.create(mid_pane, player)

  -- cross-link to try inventory transfers
  self.children.character_inventory.peer = self.children.network_items
  self.children.network_items.peer = self.children.character_inventory

  --[[ test
  for _, info in pairs(GlobalState.get_chests()) do
    local entity = info.entity
    if entity and entity.valid and entity.name == "network-chest-requester" then
      self.children.chest_inv = UiChestInventory.create(right_pane, player, entity)
      break
    end
  end
  ]]
end

function M.add_chest_inventory(self, frame)
  local vert_flow = frame.add({
    type = "frame",
    style = "character_inventory_frame",
  })
end

function M.add_net_inventory(self, frame)
end


--[[

frame: (invisible frame)
  horizontal_flow
    [character] - frame style character_gui_left_side
      464, 828
      [horizontal_flow]
        [frame_title]
        [ draggable_space_header]
        [search_bar_horizontal_flow]
          [frame_action_button - search]
        [frame_action_button - style close_button]

    [chest] - frame style "frame_without_left_and_right_side"
      467, 828
    [network items] - frame style "frame_without_left_and_right_side"
      476, 828
      [horizontal_flow]
        [frame_title]
        [ draggable_space_header]
        [search_bar_horizontal_flow]
          [frame_action_button - search]
        [frame_action_button - style close_button]


]]

-- toggles the "pinned" status and updates the window
function M.toggle_pinned(self)
  self.pinned = not self.pinned
  if self.pinned then
    self.elems.close_button.tooltip = { "gui.close" }
    self.elems.pin_button.sprite = "flib_pin_black"
    self.elems.pin_button.style = "flib_selected_frame_action_button"
    if self.player.opened == self.elems.main_window then
      self.player.opened = nil
    end
  else
    self.elems.close_button.tooltip = { "gui.close-instruction" }
    self.elems.pin_button.sprite = "flib_pin_white"
    self.elems.pin_button.style = "frame_action_button"
    self.player.opened = self.elems.main_window
  end
end

function M.on_click_refresh_button(event)
  -- needed to refresh the network item list, which can change rapidly
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    for _, ch in pairs(self.children) do
      if type(ch.refresh) == "function" then
        ch.refresh(ch)
      end
    end
  end
end

function M.on_click_close_button(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.destroy_gui(event.player_index)
  end
end

function M.on_click_pin_button(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    M.toggle_pinned(self)
  end
end

-- triggered if the GUI is removed from self.player.opened
function M.on_gui_closed(event)
  local self = M.get_gui(event.player_index)
  if self ~= nil then
    if not self.pinned then
      M.destroy_gui(event.player_index)
    end
  end
end

local function recurse_find_damage(tab)
  if tab.type == 'damage' and tab.damage ~= nil then
    return tab.damage
  end
  for k, v in pairs(tab) do
    if type(v) == 'table' then
      local rv = recurse_find_damage(v)
      if rv ~= nil then
        return rv
      end
    end
  end
  return nil
end

local function log_ammo_stuff()
  --local fuels = {} -- array { name, energy per stack }
  local ammo_list = {}
  for _, prot in pairs(game.item_prototypes) do
    if prot.type == "ammo" then
      print("-")
      clog("ammo: %s type=%s attack=%s", prot.name, prot.type, serpent.line(prot.attack_parameters))

      local at = prot.get_ammo_type()
      if at ~= nil then
        clog(" - category %s", serpent.line(at.category))
        if at.category == 'bullet' then
          local damage = recurse_find_damage(at.action)
          if damage ~= nil and type(damage.amount) == "number" then
            clog(" - damage %s", damage.amount)

            local xx = ammo_list[at.category]
            if xx == nil then
              xx = {}
              ammo_list[at.category] = xx
            end
            table.insert(xx, { name=prot.name, amount=damage.amount })
          end
        end
      end
    end
    if prot.type == "gun" then
      print("-")
      clog("gun: %s type=%s attack=%s", prot.name, prot.type, serpent.line(prot.attack_parameters))

      --[[
      for _, tt in ipairs({ "default", "player", "turret", "vehicle"}) do
        local at = prot.get_ammo_type(tt)
        if at ~= nil then
          clog(" - %s => %s", tt, serpent.line(at.category))
          local xx = ammo_list[at.category]
          if xx == nil then
            xx = {}
            ammo_list[at.category] =xx
          end
          xx[prot.name] = true
        end
      end
      ]]
    end
  end
  for k, xx in pairs(ammo_list) do
    table.sort(xx, function (a, b) return a.amount > b.amount end)
  end
  clog("####   ammo: %s", serpent.line(ammo_list))

  for _, prot in pairs(game.entity_prototypes) do
    local guns = prot.guns
    if guns ~= nil then
      clog(" - %s has guns => %s", prot.name, serpent.line(guns))
      for idx, ig in pairs(prot.indexed_guns) do
        local ap = ig.attack_parameters
        local ac = ap.ammo_categories
        clog("  ++ %s %s %s :: %s", idx, ig.name, ig.type, serpent.line(ig.attack_parameters.ammo_categories))
        --clog("   =>> ap %s", serpent.line(ap))
        for k, v in pairs(ac) do
          clog("   =>> ac %s = %s", serpent.line(k), serpent.line(v))
        end
      end
    end
  end
end

Gui.on_click(UiConstants.TV_PIN_BTN, M.on_click_pin_button)
Gui.on_click(UiConstants.TV_CLOSE_BTN, M.on_click_close_button)
Gui.on_click(UiConstants.TV_REFRESH_BTN, M.on_click_refresh_button)
-- Gui doesn't have on_gui_closed, so add it manually
Event.register(defines.events.on_gui_closed, M.on_gui_closed, Event.Filters.gui, UiConstants.TV_MAIN_FRAME)

-- hotkey handler
Event.on_event("in_open_test_view", function (event)
    M.create_gui(event.player_index)
  end)

local function request_everything(player)
  local character = player.character
  if character == nil or not player.character_personal_logistic_requests_enabled then
    return
  end

  local requests = {}
  for idx=1, character.request_slot_count do
    local rr = character.get_request_slot(idx)
    if rr ~= nil then
      requests[rr.name] = { count=rr.count, slot=idx }
    end
  end

  local items = {}
  for name, recipe in pairs(player.force.recipes) do
    --print(string.format("RECIPE: %s enabled=%s hidden=%s products=%s", recipe.name, recipe.enabled, recipe.hidden, serpent.line(recipe.products)))
    if recipe.enabled and not recipe.hidden then
      for _, pp in ipairs(recipe.products) do
        local prot = game.item_prototypes[pp.name]
        if prot ~= nil and items[pp.name] == nil then
          items[pp.name] = prot.stack_size
        end
      end
    end
  end

  local add_idx = character.request_slot_count + 1
  for item, count in pairs(items) do
    local rr = requests[item]
    if rr == nil then
      player.print(string.format("Added Reqeust for %s in slot %s", item, add_idx))
      character.set_request_slot({name=item, count=count}, add_idx)
      add_idx = add_idx + 1
    else
      if rr.count > 0 and rr.count < count then
        character.set_request_slot({name=item, count=count}, rr.slot)
      end
    end
  end
end

Event.on_event("debug-network-item", function (event)
    --GlobalState.log_queue_info()
    -- log_ammo_stuff()
    --[[ player_index, input_name, cursor_position, ]]
    local player = game.get_player(event.player_index)
    if player ~= nil and player.selected ~= nil then
      local ent = player.selected
      local unum = ent.unit_number
      clog("EVENT %s ent=[%s] %s %s", serpent.line(event), unum, ent.name, ent.type)
      local info = GlobalState.entity_info_get(unum)
      if info ~= nil then
        clog(" - %s", serpent.line(info))
      end
      if ent.type == "rocket-silo" then
        clog("%s recipe=%s allow+copy=%s", ent.name, serpent.line(ent.get_recipe().ingredients), ent.prototype.allow_copy_paste)
      end
      auto_player_request.doit(player)
      --request_everything(player)
    end
  end)

local function get_sprite_name(name)
  if game.item_prototypes[name] ~= nil then
    return "item/" .. name
  end
  if game.fluid_prototypes[name] ~= nil then
    return "fluid/" .. name
  end
end

local function update_player_selected(player)
  if player == nil then
    return
  end

  local info
  local ent = player.selected
  if ent ~= nil and ent.unit_number ~= nil then
    info = GlobalState.entity_info_get(ent.unit_number)
  end

  local gname = "MYSUPERTEST"
  local parent = player.gui.left
  local frame = parent[gname]
  if frame ~= nil then
    frame.destroy()
  end

  if info == nil then
    return
  end

  -- create the window/frame
  frame = parent.add {
    type = "frame",
    name = gname,
    --caption = "This is a test",
    style = "quick_bar_window_frame",
    --style = "tooltip_heading_label",
    --style = "tooltip_generated_from_description_frame",
    ignored_by_interaction = true,
  }

  -- create the main vertical flow
  local vflow = frame.add {
    type = "flow",
    direction = "vertical",
  }

  -- add the header
  local hdr_frame = vflow.add {
    type = "frame",
    name = gname,
    style = "tooltip_title_frame_light",
    ignored_by_interaction = true,
  }

  if ent.type == "entity-ghost" then
    hdr_frame.add {
      type="label",
      name="MYSUPERTEST-text-ghost",
      caption = 'Ghost:',
      style = "tooltip_heading_label",
      ignored_by_interaction = true,
    }
    hdr_frame.add {
      type="label",
      name="MYSUPERTEST-text",
      caption = ent.ghost_localised_name,
      style = "tooltip_heading_label",
      ignored_by_interaction = true,
    }
    else
    hdr_frame.add {
      type="label",
      name="MYSUPERTEST-text",
      caption = ent.localised_name,
      style = "tooltip_heading_label",
      ignored_by_interaction = true,
    }
    end


  -- start the description area
  local desc_flow = vflow.add {
    type = "flow",
    direction = "vertical",
  }

  --[[
  vflow.add {
    type="label",
    name="MYSUPERTEST-text",
    caption = "This is a test",
    --style = "tooltip_heading_title",
    --style = "tooltip_title_label",
    style = "tooltip_heading_label",
    ignored_by_interaction = true,
  }
  ]]
  --[[
  flow = vflow.add {
    type = "flow",
    name="MYSUPERTEST-flow",
    direction = "vertical",
    --style = "tooltip_panel_background",
  }
  ]]
  if M.super_debug == true then
    -- debug: log info
    local xi = {}
    for k, v in pairs(info) do
      if k ~= "entity" then
        xi[k] = v
      end
    end
    desc_flow.add {
      type="label",
      caption = serpent.line(xi),
      ignored_by_interaction = true,
    }
  else
    desc_flow.add {
      type="label",
      caption = string.format("unit_number: %s", info.unit_number),
      ignored_by_interaction = true,
    }
  end
  if info.service_type ~= nil then
    desc_flow.add {
      type="label",
      caption = string.format("Service type: %s", info.service_type),
      ignored_by_interaction = true,
    }
  end
  if info.service_priority ~= nil then
    desc_flow.add {
      type="label",
      caption = string.format("Service priority: %s", info.service_priority),
      ignored_by_interaction = true,
    }
  end
  if info.service_tick_delta ~= nil then
    desc_flow.add {
      type="label",
      caption = string.format("Service period: %.2f seconds", info.service_tick_delta / 60),
      ignored_by_interaction = true,
    }
  end
  if info.service_tick ~= nil then
    desc_flow.add {
      type="label",
      caption = string.format("Service tick: %s", info.service_tick),
      ignored_by_interaction = true,
    }
  end
  if info.ore_name ~= nil then
    --[[
    local hflow = desc_flow.add {
      type="flow",
      ignored_by_interaction = true,
    }
    hflow.add {
      type="label",
      caption = string.format("Ore: %s", info.ore_name),
      ignored_by_interaction = true,
    }
    ]]
    local spname = get_sprite_name(info.ore_name)
    if spname ~= nil then
      desc_flow.add {
        type = "sprite-button",
        sprite = spname,
      }
    end
  end
  if info.requests ~= nil then
    --[[
    local take_hflow = desc_flow.add {
      type="flow",
      ignored_by_interaction = true,
    }
    ]]
    local take_hflow = desc_flow.add {
      type="table",
      style="compact_slot_table",
      column_count = 7,
      ignored_by_interaction = true,
    }
    for _, r in ipairs(info.requests) do
      if r.type == "take" then
        take_hflow.add {
          type = "sprite-button",
          style="transparent_slot",
          sprite = "item/" .. r.item,
          number = r.buffer or 0,
        }
      end
    end
    local inv = ent.get_output_inventory()
    local is_locked = (inv.get_bar() < #inv)
    desc_flow.add {
      type="label",
      caption = string.format("Locked: %s", is_locked),
      ignored_by_interaction = true,
    }
  end
  if info.config ~= nil and info.config.type == "take" then
    local fluid = info.config.fluid
    if fluid ~= nil then
      local take_hflow = desc_flow.add {
        type="table",
        style="compact_slot_table",
        column_count = 7,
        ignored_by_interaction = true,
      }
      take_hflow.add {
        type = "sprite-button",
        style="transparent_slot",
        sprite = "fluid/" .. fluid,
        number = info.config.buffer or 1000,
      }
    end
    desc_flow.add {
      type="label",
      caption = string.format("%s", serpent.line(info.config)),
      ignored_by_interaction = true,
    }
    if info.fluid_addave ~= nil then
      desc_flow.add {
        type="label",
        caption = string.format("AddAve %s", math.floor(info.fluid_addave)),
        ignored_by_interaction = true,
      }
    end
  end
  if ent.name == "entity-ghost" then
    local is_ok = true
    if not ent.surface.can_place_entity({
      name = ent.ghost_name,
      position = ent.position,
      direstion = ent.direction,
      })
    then
      desc_flow.add {
        type="label",
        caption = "Blocked!",
        ignored_by_interaction = true,
      }
      is_ok = false
    end

    for _, ing in ipairs(ent.ghost_prototype.items_to_place_this) do
      local cnt = GlobalState.get_item_count(ing.name)
      if cnt < ing.count then
        desc_flow.add {
          type="label",
          caption = string.format("Missing: %s x %s", ing.count, ing.name),
          ignored_by_interaction = true,
        }
        is_ok = false
      end
    end
    if is_ok then
      desc_flow.add {
        type="label",
        caption = "Queued for build",
        ignored_by_interaction = true,
      }
    end
  end

  --string.format("[%s] %s", ent.unit_number, ent.localised_name)
  --print(string.format("name=%s type=%s", ent.name, ent.type))
  if ent.type == "assembling-machine" and ent.name == "mining-depot" then
    print(string.format("name=%s type=%s is_crafting=%s s=%s p=%s",
      ent.name, ent.type,
      ent.is_crafting(),
      ent.crafting_speed,
      ent.crafting_progress * 100))
    local r = ent.get_recipe()
    if r ~= nil then
      local rtime = r.energy / ent.crafting_speed -- time to finish one recipe
      local svc_ticks = info.service_tick_delta or (60 * 60)
      local rp = game.recipe_prototypes[r.name]
      if rp ~= nil then
        print(string.format("  overload_multiplier=%s", rp.overload_multiplier))
      end
      --[[
        calculate the amount of ingredients that should be in the input.
        Assume we service once every 60 seconds.
        If it takes 5 units for one recipe and the recipe takes 10 seconds, then we can finish
          60/10 = 6 per minute.  That means we need 6*5=30 items in the input. Anything more is a waste.
          Can be basd on the service time. Minimum is the amount reuired by the recipe.
      ]]
      local inp_inv = ent.get_inventory(defines.inventory.assembling_machine_input)
      local item_contents = inp_inv.get_contents()
      local mult = svc_ticks / (rtime * 60)
      local rmult = math.ceil(mult)
      local have = {}
      print(string.format("  energy=%s time=%s svc=%s mult=%s %s", r.energy, rtime, svc_ticks, mult, rmult))
      local needed = {} -- key=item, val=amount
      for _, ing in ipairs(r.ingredients) do
        needed[ing.name] = math.floor(math.max(ing.amount, ing.amount * rmult))
        if ing.type == "fluid" then
          have[ing.name] = ent.get_fluid_count(ing.name)
        elseif ing.type == "item" then
          have[ing.name] = item_contents[ing.name] or 0
        end
      end
      print(string.format("need=%s  have=%s  ing=%s", serpent.line(needed), serpent.line(have), serpent.line(r.ingredients)))
    end
  end

  if false then -- need 'pipe-connectable' entity
    local nn = ent.neighbours
    if nn ~= nil then
      print(string.format("neighbours: %s", serpent.line(nn)))
    end
  end

  if false then -- fuel debug
    local fuel_inv = ent.get_fuel_inventory()
    local burner = ent.burner
    if fuel_inv ~= nil and burner ~= nil then
      local eprot = game.entity_prototypes[ent.name]
      print(string.format("[%s] %s [%s] %s energy=%s/%s/%s/%s heat=%s heat_capacity=%s remaining_burning_fuel=%s",
        ent.unit_number, ent.name, ent.type,
        serpent.line(fuel_inv.get_contents()),
        ent.energy, eprot.energy_usage, eprot.max_energy_usage,  eprot.max_energy_production,
        burner.heat,
        burner.heat_capacity,
        burner.remaining_burning_fuel
      ))
      local max_energy = eprot.max_energy_usage --math.max(ent.energy, eprot.max_energy_usage)
      local cur_burn = burner.currently_burning
      if cur_burn ~= nil then
        local prot = game.item_prototypes[cur_burn.name]
        local fe = prot.fuel_value / max_energy
        print(string.format(" - [%s] %s => %s  sec=%s/%s", cur_burn.name, cur_burn.type, prot.fuel_value,
          fe, fe / 60))
      end
    end
  end
end

local function on_selected_entity_changed(event)
  update_player_selected(game.get_player(event.player_index))
end
Event.on_event(defines.events.on_selected_entity_changed, on_selected_entity_changed)

local function update_all_players_selected()
  for _, player in pairs(game.players) do
    update_player_selected(player)
  end
end
Event.on_nth_tick(60, update_all_players_selected)

-- schedule the entity service really soon if the recipe changed since the last service
local function my_on_gui_closed(event)
  local entity = event.entity
  if event.gui_type == defines.gui_type.entity and entity ~= nil and entity.type == "assembling-machine" then
    GlobalState.assembler_check_recipe(entity)
  end
end

-- Event.on_event(defines.events.on_gui_opened, my_on_gui_opened)
Event.on_event(defines.events.on_gui_closed, my_on_gui_closed)

return M
