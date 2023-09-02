local GlobalState = require "src.GlobalState"
local NetworkChestGui = require "src.NetworkChestGui"
local UiHandlers = require "src.UiHandlers"
local NetworkViewUi = require "src.NetworkViewUi"
local UiConstants = require "src.UiConstants"
local NetworkTankGui = require "src.NetworkTankGui"
local Event = require('__stdlib__/stdlib/event/event')
local clog = require("src.log_console").log
local tables_have_same_keys = require("src.tables_have_same_keys")
  .tables_have_same_keys

local M = {}

function M.on_init()
  GlobalState.setup()
end

function M.on_create(event, entity)
  local requests = {}

  if event.tags ~= nil then
    local requests_tag = event.tags.requests
    if requests_tag ~= nil then
      requests = requests_tag
    end
  end

  GlobalState.register_chest_entity(entity, requests)
end

local function generic_create_handler(event)
  local entity = event.created_entity
  if entity == nil then
    entity = event.entity
  end
  if entity.name == "network-chest" then
    M.on_create(event, entity)
  elseif entity.name == "network-tank" then
    local config = nil
    if event.tags ~= nil then
      local config_tag = event.tags.config
      if config_tag ~= nil then
        config = config_tag
      end
    end
    GlobalState.register_tank_entity(entity, config)
  elseif GlobalState.is_logistic_entity(entity.name) then
    GlobalState.logistic_add_entity(entity)
  elseif GlobalState.is_vehicle_entity(entity.name) then
    GlobalState.vehicle_add_entity(entity)
  elseif GlobalState.is_furnace_entity(entity.name) then
    GlobalState.furnace_add_entity(entity)
  end
end

function M.on_built_entity(event)
  generic_create_handler(event)
end

function M.script_raised_built(event)
  generic_create_handler(event)
end

function M.on_entity_cloned(event)
  if event.source.name ~= event.destination.name then
    return
  end
  local name = event.source.name
  if name == "network-chest" then
    GlobalState.register_chest_entity(event.destination)
    local source_info = GlobalState.get_chest_info(event.source.unit_number)
    local dest_info = GlobalState.get_chest_info(event.destination.unit_number)
    if source_info ~= nil and dest_info ~= nil then
      dest_info.requests = source_info.requests
    end
  elseif name == "network-tank" then
    GlobalState.register_tank_entity(event.source)
    GlobalState.register_tank_entity(event.destination)
    GlobalState.copy_tank_config(
      event.source.unit_number,
      event.destination.unit_number
    )
  elseif GlobalState.is_logistic_entity(name) then
    GlobalState.logistic_add_entity(event.destination)
  elseif GlobalState.is_vehicle_entity(name) then
    GlobalState.vehicle_add_entity(event.destination)
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
  if entity.unit_number == nil then
    return
  end
  if entity.name == "network-chest" then
    GlobalState.put_chest_contents_in_network(entity)
    if not opts.do_not_delete_entity then
      GlobalState.delete_chest_entity(entity.unit_number)
    end
    if global.mod.network_chest_gui ~= nil and
       global.mod.network_chest_gui.entity.unit_number == entity.unit_number
    then
      global.mod.network_chest_gui.frame.destroy()
      global.mod.network_chest_gui = nil
    end
  elseif entity.name == "network-tank" then
    GlobalState.put_tank_contents_in_network(entity)
    if not opts.do_not_delete_entity then
      GlobalState.delete_tank_entity(entity.unit_number)
    end
  elseif GlobalState.is_logistic_entity(entity.name) then
    GlobalState.put_chest_contents_in_network(entity)
    GlobalState.logistic_del(entity.unit_number)
  elseif GlobalState.is_vehicle_entity(entity.name) then
    GlobalState.vehicle_del(entity.unit_number)
  end
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
  if event.entity.name == "network-chest" then
    GlobalState.put_chest_contents_in_network(event.entity)
  elseif event.entity.name == "network-tank" then
    GlobalState.put_tank_contents_in_network(event.entity)
  end
end

function M.on_post_entity_died(event)
  if event.unit_number ~= nil then
    GlobalState.logistic_del(event.unit_number)

    local original_entity = GlobalState.get_chest_info(event.unit_number)
    if original_entity ~= nil then
      if event.ghost ~= nil then
        event.ghost.tags = { requests = original_entity.requests }
      end
      GlobalState.delete_chest_entity(event.unit_number)
    else
      -- it might be a tank
      local tank_info = GlobalState.get_tank_info(event.unit_number)
      if tank_info ~= nil then
        GlobalState.delete_tank_entity(event.unit_number)
        if event.ghost ~= nil then
          event.ghost.tags = { config = tank_info.config }
        end
      end
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
    elseif entity.name == "network-tank" then
      local real_entity = event.surface.find_entity(
        "network-tank",
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
  if dest.name == "network-chest" then
    if source.name == "network-chest" then
      GlobalState.copy_chest_requests(source.unit_number, dest.unit_number)
    else
      local recipe = source.get_recipe()
      if recipe ~= nil then
        local requests = {}
        local buffer_size = settings.global
          ["item-network-stack-size-on-assembler-paste"].value
        for _, ingredient in ipairs(recipe.ingredients) do
          if ingredient.type == "item" then
            local stack_size = game.item_prototypes[ingredient.name].stack_size
            local buffer = math.min(buffer_size, stack_size)
            table.insert(requests, {
              type = "take",
              item = ingredient.name,
              buffer = buffer,
              limit = 0,
            })
          end
        end
        GlobalState.set_chest_requests(dest.unit_number, requests)
      end
    end
  elseif dest.name == "network-tank" then
    if source.name == "network-tank" then
      GlobalState.copy_tank_config(source.unit_number, dest.unit_number)
    end
  end
end

-- fulfill requests. entity must have request_slot_count and get_request_slot()
-- useful for vehicles (spidertron) and logistic containers
function M.inventory_handle_requests(entity, inv, old_status)
  local status = old_status or GlobalState.UPDATE_STATUS.NOT_UPDATED
  if entity ~= nil and inv ~= nil and entity.request_slot_count > 0 then
    local contents = inv.get_contents()

    for slot = 1, entity.request_slot_count do
      local req = entity.get_request_slot(slot)
      if req ~= nil and req.name ~= nil then
        local current_count = contents[req.name] or 0
        local network_count = GlobalState.get_item_count(req.name)
        local n_wanted = math.max(0, req.count - current_count)
        local n_transfer = math.min(network_count, n_wanted)
        if n_transfer > 0 then
          local n_inserted = inv.insert { name = req.name, count = n_transfer }
          if n_inserted > 0 then
            GlobalState.set_item_count(req.name, network_count - n_inserted)
            status = GlobalState.UPDATE_STATUS.UPDATED
          end
        end
        if n_transfer < n_wanted then
          GlobalState.missing_item_set(req.name, entity.unit_number, n_wanted - n_transfer)
        end
      end
    end
  end
  return status
end

function M.updatePlayers()
  if not global.mod.network_chest_has_been_placed then
    return
  end

  for _, player in pairs(game.players) do
    local enable_trash = settings.get_player_settings(player.index)
      ["item-network-enable-player-logistics"].value

    if enable_trash then
      -- put all trash into network
      GlobalState.put_inventory_in_network(player.get_inventory(defines.inventory.character_trash))

      -- get contents of player inventory
      local main_inv = player.get_inventory(defines.inventory.character_main)
      if main_inv ~= nil then
        local character = player.character
        if character ~= nil and character.character_personal_logistic_requests_enabled then
          local main_contents = main_inv.get_contents()
          local cursor_stack = player.cursor_stack
          if cursor_stack ~= nil and cursor_stack.valid_for_read then
            main_contents[cursor_stack.name] =
              (main_contents[cursor_stack.name] or 0) + cursor_stack.count
          end

          -- scan logistic slots and transfer to character
          for logistic_idx = 1, character.request_slot_count do
            local param = player.get_personal_logistic_slot(logistic_idx)
            if param ~= nil and param.name ~= nil then
              local available_in_network = GlobalState.get_item_count(param.name)
              local current_amount = main_contents[param.name] or 0
              local delta = math.min(available_in_network,
                math.max(0, param.min - current_amount))
              if delta > 0 then
                local n_transfered = main_inv.insert({
                  name = param.name,
                  count = delta,
                })
                GlobalState.set_item_count(
                  param.name,
                  available_in_network - n_transfered
                )
              end
            end
          end
        end
      end
    end
  end
end

function M.update_vehicle(entity, inv_trash, inv_trunk)
  -- move trash to the item network
  local status = GlobalState.put_inventory_in_network(inv_trash)

  return M.inventory_handle_requests(entity, inv_trunk, status)
end

function M.vehicle_update_entity(entity)
  -- only 1 logistic vehicle right now
  if entity.name ~= "spidertron" then
    return GlobalState.UPDATE_STATUS.INVALID
  end

  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED
  if entity.vehicle_logistic_requests_enabled then
    status = M.update_vehicle(entity,
      entity.get_inventory(defines.inventory.spider_trash),
      entity.get_inventory(defines.inventory.spider_trunk))
  end
  return status
end

function M.furnace_update_entity(entity)
  if not entity.valid then
    return GlobalState.UPDATE_STATUS.INVALID
  end
  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED

  -- try to top off the fuel
  local fuel_name = "coal"
  local n_avail = GlobalState.get_item_count(fuel_name)
  local inv = entity.get_fuel_inventory()
  if inv ~= nil then
    local fuel_count = inv.get_item_count(fuel_name)
    local n_wanted = 5
    if fuel_count < n_wanted then
      local n_trans = math.max(0, math.min(n_avail, n_wanted - fuel_count))
      if n_trans > 0 then
        local n_added = inv.insert({name = fuel_name, count = n_trans })
        if n_added > 0 then
          --clog("loaded %s (%s) info %s", fuel_count, n_added, entity.name)
          GlobalState.increment_item_count(fuel_name, -n_added)
          status = GlobalState.UPDATE_STATUS.UPDATED
        end
      end
    end
  end

  -- take any full stacks
  inv = entity.get_output_inventory()
  if inv ~= nil then
    for idx = 1, #inv do
      local stack = inv[idx]
      if stack.valid_for_read and stack.count > 5 then
        GlobalState.increment_item_count(stack.name, stack.count)
        stack.clear()
        status = GlobalState.UPDATE_STATUS.UPDATED
      end
    end
  end
  return status
end

function M.is_request_valid(request)
  return request.item ~= nil and request.buffer_size ~= nil and
    request.limit ~= nil
end

--------------------------------------------------------------------------------

-- Reset a locked inventory.
-- Filters can only be before the bar, so we only clear up to that point.
local function inv_reset(inv)
  inv.clear()
  local bar_idx = inv.get_bar()
  if bar_idx < #inv then
    for idx = 1, bar_idx - 1 do
      inv.set_filter(idx, nil)
    end
    inv.set_bar()
  end
end

--[[
  (re)lock an unconfigured chest.
  We create one slot for each recent_item that isn't in leftovers.
  Then we remember the first empty slot as the bar index.
  Then we add all the leftovers and set the bar.
]]
local function inv_unconfigured_lock(inv, leftovers, recent_items)
  inv_reset(inv)

  -- add filtered slots for recent items NOT in leftovers
  local f_idx = 1
  for item, _ in pairs(recent_items) do
    -- create a filtered slot for each item we have seen recently that doesn't have items
    -- Limit to the most recent 8 items
    if leftovers[item] == nil then
      inv.set_filter(f_idx, item)
      f_idx = f_idx + 1
      if f_idx > #inv - 4 then
        break
      end
    end
  end

  -- add the leftover items (no need to filter)
  for item, count in pairs(leftovers) do
    -- add leftovers to the chest. anything that didn't fit goes to the net
    local n_sent = inv.insert({name = item, count = count})
    if count > n_sent then
      GlobalState.increment_item_count(item, count - n_sent)
    end
  end

  -- set the bar on the first left-over
  inv.set_bar(f_idx)
end

--[[
Updates a chest if there are no requests.
Anything in the chest is forwarded to the item-network.
If anything can't be forwarded, the chest is locked (set bar=1) and the leftovers stay in the chest.
]]
local function update_network_chest_unconfigured_unlocked(info, inv, contents)
  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED

  -- We will re-add anything that cannot be sent when we lock the chest
  inv.clear()

  -- move everything to the network, calculating leftovers
  local leftovers = {}
  for item, count in pairs(contents) do
    if count > 0 then
      local n_free = GlobalState.get_insert_count(item)
      local n_transfer = math.min(count, n_free)
      if n_transfer > 0 then
        info.recent_items[item] = game.tick
        GlobalState.increment_item_count(item, n_transfer)
        status = GlobalState.UPDATE_STATUS.UPDATED
        count = count - n_transfer
      end

      if count > 0 then
        leftovers[item] = count
      end
    end
  end

  -- if there are any leftovers, we put them back and lock the chest
  if next(leftovers) ~= nil then
    --GlobalState.log_entity("UNCONF LOCK", info.entity)
    info.locked_items = leftovers
    inv_unconfigured_lock(inv, leftovers, info.recent_items)
    status = GlobalState.UPDATE_STATUS.UPDATED
  end
  return status
end

--[[
Updates a chest if there are no requests.
Anything in the chest is forwarded to the item-network.
If anything can't be forwarded, the chest is locked (set bar=1) and the leftovers stay in the chest.
This does not call inv.clear(), but rather pulls items using inv.remove().
]]
local function update_network_chest_unconfigured_locked(info, inv, contents)
  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED

  -- NOTE: We do not clear the inventory or filters. There is one slot per item.

  -- move everything to the network, calculating leftovers
  local leftovers = {}
  for item, count in pairs(contents) do
    if count > 0 then
      local n_free = GlobalState.get_insert_count(item)
      local n_transfer = math.min(count, n_free)
      if n_transfer > 0 then
        info.recent_items[item] = game.tick
        GlobalState.increment_item_count(item, n_transfer)
        inv.remove({name=item, count=n_transfer})
        status = GlobalState.UPDATE_STATUS.UPDATED
        count = count - n_transfer
      end
      if count > 0 then
        -- Since there is one slot per item, count will be <= stack_size.
        leftovers[item] = count
      end
    end
  end

  -- check if the list of locked items changed
  if tables_have_same_keys(info.locked_items, leftovers) then
    -- nope! we are done.
    return status
  end
  info.locked_items = leftovers

  -- See if we can unlock the chest (chest is empty)
  if next(leftovers) == nil then
    -- the chest is now empty, so unlock it
    --GlobalState.log_entity("UNCONF UNLOCK", info.entity)
    inv_reset(inv)
  else
    -- need to re-lock the chest
    --GlobalState.log_entity("UNCONF RE-LOCK", info.entity)
    inv_unconfigured_lock(inv, leftovers, info.recent_items)
  end

  return GlobalState.UPDATE_STATUS.UPDATED
end

-- get the "buffer" value for this item
local function get_request_buffer(requests, item)
  for _, rr in ipairs(requests) do
    if rr.item == item then
      return rr.buffer, rr.type
    end
  end
  return 0, "give"
end

local function inv_filter_slots(inv, item, inv_idx, count)
  for _ = 1, count do
    inv.set_filter(inv_idx, item)
    inv_idx = inv_idx + 1
  end
  return inv_idx
end

--[[
  Lock a configured chest.

  inv = the inventory (info.entity.get_output_inventory())
  contents = the remaining contents, key=item_name, val=count
  info.locked_items = the items that are in the locked state
  info.recent_items = the items that have been in the chest recently
]]
local function inv_configured_lock(info, inv, contents)
  -- the configured chest needs to be locked, so we re-add contents
  inv_reset(inv)

  -- going to sort requests into two sections: before and after the bar
  local slots_unlocked = {}
  local slots_locked = {}
  local locked_items = info.locked_items or {}

  -- add "take" request filters
  for _, req in pairs(info.requests) do
    local stack_size = game.item_prototypes[req.item].stack_size
    local n_slots = math.floor((req.buffer + stack_size - 1) / stack_size)
    if req.type == "take" then
      slots_unlocked[req.item] = n_slots
    else
      -- provider needs 1 slot to buffer 0 items
      n_slots = math.min(1, n_slots)

      if locked_items[req.item] == nil then
        slots_unlocked[req.item] = n_slots
      else
        slots_locked[req.item] = n_slots
      end
    end
  end

  -- add one slot for any item we have seen, but isn't in the chest
  for name, _ in pairs(info.recent_items) do
    if slots_unlocked[name] == nil and slots_locked[name] == nil then
      slots_unlocked[name] = 1
    end
  end

  -- now set the provider filters and the bar
  local inv_idx = 1
  for item, n_slots in pairs(slots_unlocked) do
    inv_idx = inv_filter_slots(inv, item, inv_idx, n_slots)
  end
  local bar_idx = inv_idx
  for item, n_slots in pairs(slots_locked) do
    inv_idx = inv_filter_slots(inv, item, inv_idx, n_slots)
  end
  -- add the contents and set the bar to lock
  for name, count in pairs(contents) do
    if count > 0 then
      inv.insert({name=name, count=count})
    end
  end
  inv.set_bar(bar_idx)
end

--[[
  Common bit for a configured chest.
  Push items to the net, then handle "take" requests
]]
local function update_network_chest_configured_common(info, inv, contents)
  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED
  local locked_items = {} -- key=item, val=true

  -- pass 1: Send excessive items; note which sends fail in "locked" table
  for item, n_have in pairs(contents) do
    local n_want, r_type = get_request_buffer(info.requests, item)

    -- try to send to the network if we have too many
    local n_extra = n_have - n_want
    if n_extra > 0 then
      local n_free = GlobalState.get_insert_count(item)
      local n_transfer = math.min(n_extra, n_free)
      if n_transfer > 0 then
        status = GlobalState.UPDATE_STATUS.UPDATED
        inv.remove({name=item, count=n_transfer})
        GlobalState.increment_item_count(item, n_transfer)
        info.recent_items[item] = game.tick
        n_have = n_have - n_transfer
        contents[item] = n_have
      end
      if n_have > n_want and r_type ~= "take" then
        -- add to the locked area (provider unable to provide)
        locked_items[item] = true
      end
    end
  end

  -- pass 2: satisfy requests (pull into contents)
  for _, req in pairs(info.requests) do
    if req.type == "take" then
      local n_have = contents[req.item] or 0
      local n_innet = GlobalState.get_item_count(req.item)
      local n_avail = math.max(0, n_innet - req.limit)
      local n_want = req.buffer
      if n_want > n_have then
        local n_transfer = math.min(n_want - n_have, n_avail)
        if n_transfer > 0 then
          -- it may not fit in the chest due to other reasons
          n_transfer = inv.insert({name=req.item, count=n_transfer})
          if n_transfer > 0 then
            status = GlobalState.UPDATE_STATUS.UPDATED
            contents[req.item] = n_have + n_transfer
            GlobalState.set_item_count(req.item, n_innet - n_transfer)

            --[[ If we filled the entire buffer AND there is enough in the net for another buffer, then
            we are probably not requesting enough. Up the buffer size by 1.
            ]]
            if n_transfer == req.buffer and n_innet > n_transfer * 4 then
              req.buffer = req.buffer + 1
            end
          end
        else
          GlobalState.missing_item_set(req.item, info.entity.unit_number, n_want - n_have)
        end
      end
    end
  end

  return status, locked_items
end

--[[
  Update the chest in the configured-unlocked state.
  Transitions to locked if an item can't be pushed to the network.
]]
local function update_network_chest_configured_unlocked(info, inv, contents)
  local status, locked_items = update_network_chest_configured_common(info, inv, contents)

  -- is the chest still unlocked? if so, we are done.
  if next(locked_items) == nil then
    info.locked_items = nil
    return status
  end
  info.locked_items = locked_items

  inv_configured_lock(info, inv, contents)

  return GlobalState.UPDATE_STATUS.UPDATED
end

--[[
Process a configured, locked chest.
]]
local function update_network_chest_configured_locked(info, inv, contents)
  local status, locked_items = update_network_chest_configured_common(info, inv, contents)

  -- check if the list of locked items changed
  if tables_have_same_keys(info.locked_items, locked_items) then
    return status
  end

  -- can we unlock the chest?
  if next(locked_items) == nil then
    info.locked_items = nil
    -- we no longer have too much stuff, so we can unlock
    for idx = 1, inv.get_bar() do
      inv.set_filter(idx, nil)
    end
    inv.set_bar()
  else
    -- the list of locked items changed, so we need to re-lock the chest
    info.locked_items = locked_items
    inv_configured_lock(info, inv, contents)
  end

  return GlobalState.UPDATE_STATUS.UPDATED
end

local function update_network_chest(info)
  local inv = info.entity.get_output_inventory()
  local contents = inv.get_contents()

  -- make sure recent_items is present (can get cleared elsewhere)
  if info.recent_items == nil then
    info.recent_items = {}
  end

  local is_locked = (inv.get_bar() < #inv)
  if #info.requests == 0 then
    if is_locked then
      return update_network_chest_unconfigured_locked(info, inv, contents)
    else
      return update_network_chest_unconfigured_unlocked(info, inv, contents)
    end
  else
    if is_locked then
      return update_network_chest_configured_locked(info, inv, contents)
    else
      return update_network_chest_configured_unlocked(info, inv, contents)
    end
  end
end

local function update_tank(info)
  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED
  local type = info.config.type
  local limit = info.config.limit
  local buffer = info.config.buffer
  local fluid = info.config.fluid
  local temp = info.config.temperature

  if type == "give" then
    local fluidbox = info.entity.fluidbox
    for idx = 1, #fluidbox do
      local fluid_instance = fluidbox[idx]
      if fluid_instance ~= nil then
        local current_count = GlobalState.get_fluid_count(
          fluid_instance.name,
          fluid_instance.temperature
        )
        local key = GlobalState.fluid_temp_key_encode(fluid_instance.name, fluid_instance.temperature)
        local gl_limit = GlobalState.get_limit(key)
        local n_give = math.max(0, fluid_instance.amount)
        local n_take = math.max(0, math.max(limit, gl_limit) - current_count)
        local n_transfer = math.floor(math.min(n_give, n_take))
        if n_transfer > 0 then
          status = GlobalState.UPDATE_STATUS.UPDATED
          GlobalState.increment_fluid_count(fluid_instance.name,
            fluid_instance.temperature, n_transfer)
          local removed = info.entity.remove_fluid({
            name = fluid_instance.name,
            temperature = fluid_instance.temperature,
            amount = n_transfer,
          })
          assert(removed == n_transfer)
        end
      end
    end
  else
    local fluidbox = info.entity.fluidbox
    local tank_fluid = nil
    local tank_temp = nil
    local tank_count = 0
    local n_fluid_boxes = 0
    for idx = 1, #fluidbox do
      local fluid_instance = fluidbox[idx]
      if fluid_instance ~= nil then
        n_fluid_boxes = n_fluid_boxes + 1
        tank_fluid = fluid_instance.name
        tank_temp = fluid_instance.temperature
        tank_count = fluid_instance.amount
      end
    end

    if n_fluid_boxes == 0 or (n_fluid_boxes == 1 and tank_fluid == fluid and tank_temp == temp) then
      local network_count = GlobalState.get_fluid_count(
        fluid,
        temp
      )
      local n_give = math.max(0, network_count - limit)
      local n_take = math.max(0, buffer - tank_count)
      local n_transfer = math.floor(math.min(n_give, n_take))
      if n_transfer > 0 then
        status = GlobalState.UPDATE_STATUS.UPDATED
        local added = info.entity.insert_fluid({
          name = fluid,
          amount = n_transfer,
          temperature = temp,
        })
        if added > 0 then
          GlobalState.increment_fluid_count(fluid, temp, -added)
        end
      end
      if n_take > n_give then
        GlobalState.missing_fluid_set(fluid, temp, info.entity.unit_number,
          n_take - n_give)
      end
    end
  end

  return status
end

local function update_chest_entity(unit_number, info)
  local entity = info.entity
  if not entity.valid then
    return GlobalState.UPDATE_STATUS.INVALID
  end

  if entity.to_be_deconstructed() then
    return GlobalState.UPDATE_STATUS.NOT_UPDATED
  end

  return update_network_chest(info)
end

local function update_tank_entity(unit_number, info)
  local entity = info.entity
  if not entity.valid then
    return GlobalState.UPDATE_STATUS.INVALID
  end

  if info.config == nil or entity.to_be_deconstructed() then
    return GlobalState.UPDATE_STATUS.NOT_UPDATED
  end

  return update_tank(info)
end

local function update_entity(unit_number)
  local info
  info = GlobalState.get_chest_info(unit_number)
  if info ~= nil then
    return update_chest_entity(unit_number, info)
  end

  info = GlobalState.get_tank_info(unit_number)
  if info ~= nil then
    return update_tank_entity(unit_number, info)
  end

  local entity = GlobalState.get_logistic_entity(unit_number)
  if entity ~= nil then
    return M.logistic_update_entity(entity)
  end

  entity = GlobalState.get_vehicle_entity(unit_number)
  if entity ~= nil then
    return M.vehicle_update_entity(entity)
  end

  entity = GlobalState.get_furnace_entity(unit_number)
  if entity ~= nil then
    return M.furnace_update_entity(entity)
  end

  return GlobalState.UPDATE_STATUS.INVALID
end

function M.update_queue()
  GlobalState.update_queue(update_entity)
end

function M.logistic_update_entity(entity)
  if not settings.global["item-network-enable-logistic-chest"].value then
    return GlobalState.UPDATE_STATUS.NOT_UPDATED
  end

  -- sanity check
  if not entity.valid then
    return GlobalState.UPDATE_STATUS.INVALID
  end

  -- don't add stuff to a doomed chest
  if entity.to_be_deconstructed() then
    return GlobalState.UPDATE_STATUS.NOT_UPDATED
  end

  local status = GlobalState.UPDATE_STATUS.NOT_UPDATED

  return M.inventory_handle_requests(entity, entity.get_output_inventory(), status)
end

function M.onTick()
  GlobalState.setup()
  M.update_queue()
end

function M.onTick_60()
  M.updatePlayers()
  M.check_alerts()
end

function M.handle_missing_material(entity, missing_name, item_count)
  item_count = item_count or 1
  -- a cliff doesn't have a unit_number, so fake one based on the position
  local key = entity.unit_number
  if key == nil then
    key = string.format("%s,%s", entity.position.x, entity.position.y)
  end

  -- did we already transfer something for this ghost/upgrade?
  if GlobalState.alert_transfer_get(key) == true then
    return
  end

  -- make sure it is something we can handle
  local name, count = GlobalState.resolve_name(missing_name)
  if name == nil then
    return
  end
  count = count or item_count

  -- do we have an item to send?
  local network_count = GlobalState.get_item_count(name)
  if network_count < count then
    GlobalState.missing_item_set(name, key, count)
    return
  end

  -- Find a construction network with a construction robot that covers this position
  local nets = entity.surface.find_logistic_networks_by_construction_area(
    entity.position, "player")
  for _, net in ipairs(nets) do
    if net.all_construction_robots > 0 then
      local n_inserted = net.insert({ name = name, count = count })
      if n_inserted > 0 then
        GlobalState.increment_item_count(name, -n_inserted)
        GlobalState.alert_transfer_set(key)
        return
      end
    end
  end
end

function M.check_alerts()
  GlobalState.alert_transfer_cleanup()

  -- process all the alerts for all players
  for _, player in pairs(game.players) do
    local alerts = player.get_alerts {
      type = defines.alert_type.no_material_for_construction }
    for _, xxx in pairs(alerts) do
      for _, alert_array in pairs(xxx) do
        for _, alert in ipairs(alert_array) do
          if alert.target ~= nil then
            local entity = alert.target
            -- we only care about ghosts and items that are set to upgrade
            if entity.name == "entity-ghost" or entity.name == "tile-ghost" then
              M.handle_missing_material(entity, entity.ghost_name)
            elseif entity.name == "cliff" then
              M.handle_missing_material(entity, "cliff-explosives")
            elseif entity.name == "item-request-proxy" then
              for k, v in pairs(entity.item_requests) do
                M.handle_missing_material(entity, k, v)
              end
            else
              local tent = entity.get_upgrade_target()
              if tent ~= nil then
                M.handle_missing_material(entity, tent.name)
              else
                GlobalState.log_entity("Missing", entity)
              end
            end
          end
        end
      end
    end
  end

  -- send repair packs
  for _, player in pairs(game.players) do
    local alerts = player.get_alerts {
      type = defines.alert_type.not_enough_repair_packs }
    for _, xxx in pairs(alerts) do
      for _, alert_array in pairs(xxx) do
        for _, alert in ipairs(alert_array) do
          if alert.target ~= nil then
            M.handle_missing_material(alert.target, "repair-pack")
          end
        end
      end
    end
  end
end

-------------------------------------------
-- GUI Section
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
  elseif event.gui_type == defines.gui_type.entity and event.entity.name == "network-tank" then
    local entity = event.entity
    assert(GlobalState.get_tank_info(entity.unit_number) ~= nil)

    local player = game.get_player(event.player_index)
    if player == nil then
      return
    end

    NetworkTankGui.on_gui_opened(player, entity)
  end
end

function M.on_gui_closed(event)
  local frame = event.element
  if frame ~= nil and frame.name == UiConstants.NV_FRAME then
    NetworkViewUi.on_gui_closed(event)
  elseif frame ~= nil and frame.name == UiConstants.NT_MAIN_FRAME then
    NetworkTankGui.on_gui_closed(event)
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

Event.on_nth_tick(1, M.onTick)
Event.on_nth_tick(60, M.onTick_60)
-- Event.on_nth_tick(60 * 3, M.on_every_5_seconds)

Event.on_init(function()
  M.on_init()
end)

return M
