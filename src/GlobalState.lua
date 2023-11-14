local Queue = require "src.Queue"
local tables_have_same_keys = require("src.tables_have_same_keys")
  .tables_have_same_keys
local constants = require "src.constants"
local clog = require("src.log_console").log

local M = {}

M.get_default_limit = require("src.DefaultLimits").get_default_limit

local setup_has_run = false

function M.setup()
  if setup_has_run then
    return
  end
  setup_has_run = true

  M.inner_setup()
end

--[[
Service Queue Revamp.

There is an array of queues.
The current queue is consumed until empty. Same 20-ish entities per tick.
Each queue is assigned a minimum amount of ticks that it occupies. (20 ticks?)
When a queue is empty, game.tick is compared against the deadline. If passed, then
the active queue index is incremented (and wrapped) and the deadline is reset.

Entities are added to the service queue via a unit_number and priority.
The priority selects the relative queue to insert.
 0 = active + 1
 1 = active + 2, etc
The max priority is the number of queues - 1.
Smaller priority values are serviced sooner. (0=highest, NUM_QUEUES-1=lowest)

The priority changes based on the type and whether anything was transferred.
Everything starts at priotirty 0 when created/added.

  - Network Bulk Provider (empties everything from the chest)
    * always lowest priority, empties everything

  - Network Bulk Requester (one item, grabs as much as possible, not yet implemented)
    * always lowest priority, fills entire chest (set RED stuff to limit)
    * NOTE: based on the logistic storage chest, where the filter sets the request. Coverage disabled.

  - Network Chest
    * priority goes up by 1 when something was added AND any request was empty
      * the individual request size is altered only if at highest priority (0 or 1)
    * priority goes down by 1 when nothing was added (wait longer next cycle)
    * this should auto-tune

  - Network Tank (send/provide)
    * If the tank was over 90% full AND we send the whole tank, then the priority goes up by 1 (more often)
    * If the tank was < 10% full OR we can't send the whole tanke, then the priority does down by 1 (less often)

  - Network Tank (take/request)
    * priority goes up by 1 if the tank is < 10% full when serviced and the tank is full when done
    * priority goes down by 1 if the tank is > 90% full OR we add less than 10%

  - Vechicles
    * Always lowest priority (vehicles take a while to use up stuff)

  - Logistics
    * Always lowest priority (no rush -- let the robots scurry)
]]

function M.inner_setup()
  if global.mod == nil then
    global.mod = {
      rand = game.create_random_generator(),
      chests = {},
      items = {},
    }
  end

  if global.mod.scan_queues == nil or true then
    global.mod.entity_priority = {} -- key=unum, val=priority
    M.reset_queues()
  end

  M.remove_old_ui()
  if global.mod.player_info == nil then
    global.mod.player_info = {}
  end

  if global.mod.network_chest_has_been_placed == nil then
    global.mod.network_chest_has_been_placed = true -- (global.mod.scan_queue.size + global.mod.scan_queue_inactive.size) > 0
  end

  if global.mod.fluids == nil then
    global.mod.fluids = {}
  end
  if global.mod.missing_item == nil then
    global.mod.missing_item = {} -- missing_item[item][unit_number] = { game.tick, count }
  end
  if global.mod.missing_fluid == nil then
    global.mod.missing_fluid = {} -- missing_fluid[key][unit_number] = { game.tick, count }
  end
  if global.mod.tanks == nil then
    global.mod.tanks = {}
  end

  if global.mod.vehicles == nil then
    global.mod.vehicles = {} -- vehicles[unit_number] = entity
    M.vehicle_scan_surfaces()
  end

  if global.mod.logistic == nil then
    global.mod.logistic = {} -- key=unit_number, val=entity
  end
  if global.mod.logistic_names == nil then
    global.mod.logistic_names = {} -- key=item name, val=logistic_mode from prototype
  end
  local logistic_names = M.logistic_scan_prototypes()
  if not tables_have_same_keys(logistic_names, global.mod.logistic_names) then
    global.mod.logistic_names = logistic_names
    global.mod.logistic = {}
    M.logistic_scan_surfaces()
  end

  if global.mod.alert_trans == nil then
    global.mod.alert_trans = {} -- alert_trans[unit_number] = game.tick
  end

  if not global.mod.has_run_fluid_temp_conversion then
    local new_fluids = {}
    for fluid, count in pairs(global.mod.fluids) do
      local default_temp = game.fluid_prototypes[fluid].default_temperature
      new_fluids[fluid] = {}
      new_fluids[fluid][default_temp] = count
    end
    global.mod.fluids = new_fluids
    local n_tanks = 0
    for _, entity in pairs(global.mod.tanks) do
      n_tanks = n_tanks + 1
      if entity.config ~= nil then
        entity.config.temperature =
          game.fluid_prototypes[entity.config.fluid].default_temperature
      end
    end
    if n_tanks > 0 then
      clog(
        "Migrated Item Network fluids to include temperatures. Warning: If you provide a fluid at a non-default temperature (like steam), you will have to update every requester tank to use the new fluid temperature.")
    end
    global.mod.has_run_fluid_temp_conversion = true
  end

  if global.mod.sensors == nil then
    global.mod.sensors = {}
  end

  if global.mod.item_limits == nil then
    global.mod.item_limits = {}
    M.limit_scan()
  end
  -- TEST: remove when good
  --M.limit_scan()

  -- TEST: reset the queues; causes desync in multiplayer
  --M.reset_queues()
end

function M.reset_queues()
  global.mod.scan_deadline = 0 -- keep doing nothing until past this tick
  global.mod.scan_index = 1 -- working on the queue in this index

  global.mod.scan_queues = {} -- list of queues to process
  for idx = 1, constants.QUEUE_COUNT do
    global.mod.scan_queues[idx] = Queue.new()
  end

  if global.mod.chests ~= nil then
    for unum, _ in pairs(global.mod.chests) do
      M.queue_insert(unum, 1)
    end
  end
  if global.mod.tanks ~= nil then
    for unum, _ in pairs(global.mod.tanks) do
      M.queue_insert(unum, 2)
    end
  end
  if global.mod.vehicles ~= nil then
    for unum, _ in pairs(global.mod.vehicles) do
      M.queue_insert(unum, 3)
    end
  end
  if global.mod.logistic ~= nil then
    for unum, _ in pairs(global.mod.logistic) do
      M.queue_insert(unum, 4)
    end
  end
end

-- scan existing tanks and chests and use the max "give" limit as the item limit
function M.limit_scan(item)
  local limits = global.mod.item_limits
  local unlimited = 2000000000 -- "2G"

  for _, info in pairs(global.mod.chests) do
    if info.requests ~= nil then
      for _, req in ipairs(info.requests) do
        if req.type == "give" then
          local old_limit = limits[req.item]
          local new_limit = req.limit
          if req.no_limit == true then
            new_limit = unlimited
          end
          if old_limit == nil or old_limit < new_limit then
            limits[req.item] = new_limit
          end
        end
      end
    end
  end

  for _, info in pairs(global.mod.tanks) do
    local config = info.config
    if config ~= nil then
      if config.type == "give" then
        if config.temperature ~= nil and config.fluid ~= nil then
          local key = M.fluid_temp_key_encode(config.fluid, config.temperature)
          local old_limit = limits[key]
          local new_limit = config.limit
          if config.no_limit == true then
            new_limit = unlimited
          end
          if old_limit == nil or old_limit < new_limit then
            limits[config.fluid] = new_limit
            --game.print(string.format("updated limit %s %s", key, config.limit))
          end
        end
      end
    end
  end
end

local function str_endswith(text, tag)
  if type(text) == "string" and type(tag) == "string" then
    return #tag <= #text and string.sub(text, 1 + #text - #tag) == tag
  end
  return false
end

function M.get_limits()
  return global.mod.item_limits
end

function M.get_limit(item_name)
  return global.mod.item_limits[item_name] or M.get_default_limit(item_name)
end

function M.clear_limit(item_name)
  global.mod.item_limits[item_name] = nil
end

-- set the limit, return true if it changed
function M.set_limit(item_name, value)
  if type(item_name) == "string" then
    -- don't use get_limit()
    local old_value = global.mod.item_limits[item_name]
    value = tonumber(value)
    if value ~= nil then
      -- some game code paths use a int32 for the item count
      value = math.min(value, 2000000000)
      if value ~= old_value then
        global.mod.item_limits[item_name] = value
        return true
      end
    end
  end
  return false
end

-- get the number of items that we are allowed to put in the network
function M.get_insert_count(item_name)
  return math.max(0, M.get_limit(item_name) - M.get_item_count(item_name))
end

-- store the missing item: mtab[item_name][unit_number] = { game.tick, count }
local function missing_set(mtab, item_name, unit_number, count)
  local tt = mtab[item_name]
  if tt == nil then
    tt = {}
    mtab[item_name] = tt
  end
  tt[unit_number] = { game.tick, count }
end

-- filter the missing table and return: missing[item] = count
local function missing_filter(tab)
  local deadline = game.tick - constants.MAX_MISSING_TICKS
  local missing = {}
  local to_del = {}
  for name, xx in pairs(tab) do
    for unit_number, ii in pairs(xx) do
      local tick = ii[1]
      local count = ii[2]
      if tick < deadline then
        table.insert(to_del, { name, unit_number })
      else
        missing[name] = (missing[name] or 0) + count
      end
    end
  end
  for _, ii in ipairs(to_del) do
    local name = ii[1]
    local unum = ii[2]
    tab[name][unum] = nil
    if next(tab[name]) == nil then
      tab[name] = nil
    end
  end
  return missing
end

-- mark an item as missing
function M.missing_item_set(item_name, unit_number, count)
  missing_set(global.mod.missing_item, item_name, unit_number, count)
end

-- drop any items that have not been missing for a while
-- returns the (read-only) table of missing items
function M.missing_item_filter()
  return missing_filter(global.mod.missing_item)
end

-- create a string 'key' for a fluid@temp
function M.fluid_temp_key_encode(fluid_name, temp)
  return string.format("%s@%d", fluid_name, math.floor(temp * 1000))
end

-- split the key back into the fluid and temp
function M.fluid_temp_key_decode(key)
  local idx = string.find(key, "@")
  if idx ~= nil then
    return string.sub(key, 1, idx - 1), tonumber(string.sub(key, idx + 1)) / 1000
  end
  return key, nil
end

-- mark a fluid/temp combo as missing
function M.missing_fluid_set(name, temp, unit_number, count)
  local key = M.fluid_temp_key_encode(name, temp)
  missing_set(global.mod.missing_fluid, key, unit_number, count)
end

-- drop any fluids that have not been missing for a while
-- returns the (read-only) table of missing items
function M.missing_fluid_filter()
  return missing_filter(global.mod.missing_fluid)
end

function M.remove_old_ui()
  if global.mod.network_chest_gui ~= nil then
    global.mod.network_chest_gui = nil
    for _, player in pairs(game.players) do
      local main_frame = player.gui.screen["network-chest-main-frame"]
      if main_frame ~= nil then
        main_frame.destroy()
      end

      main_frame = player.gui.screen["add-request"]
      if main_frame ~= nil then
        main_frame.destroy()
      end
    end
  end
end

-- this tracks that we already transferred an item for the request
function M.alert_transfer_set(unit_number)
  global.mod.alert_trans[unit_number] = game.tick
end

-- get whether we have already transferred for this alert
-- the item won't necessarily go where we want it
function M.alert_transfer_get(unit_number)
  return global.mod.alert_trans[unit_number] ~= nil
end

-- throw out stale entries, allowing another transfer
function M.alert_transfer_cleanup()
  local deadline = game.tick - constants.ALERT_TRANSFER_TICKS
  local to_del = {}
  for unum, tick in pairs(global.mod.alert_trans) do
    if tick < deadline then
      table.insert(to_del, unum)
    end
  end
  for _, unum in ipairs(to_del) do
    global.mod.alert_trans[unum] = nil
  end
end

function M.rand_hex(len)
  local chars = {}
  for _ = 1, len do
    table.insert(chars, string.format("%x", math.floor(global.mod.rand() * 16)))
  end
  return table.concat(chars, "")
end

--[[
function M.shuffle(list)
  for i = #list, 2, -1 do
    local j = global.mod.rand(i)
    list[i], list[j] = list[j], list[i]
  end
end
]]

-- get a table of all logistic item names that we should supply
-- called once at each startup to see if the chest list changed
function M.logistic_scan_prototypes()
  local info = {} -- key=name, val=logistic_mode
  -- find all with type="logistic-container" and (logistic_mode="requester" or logistic_mode="buffer")
  for name, prot in pairs(game.get_filtered_entity_prototypes { {
    filter = "type",
    type = "logistic-container",
  } }) do
    if prot.logistic_mode == "requester" or prot.logistic_mode == "buffer" then
      info[name] = prot.logistic_mode
    end
  end
  return info
end

function M.is_logistic_entity(item_name)
  return global.mod.logistic_names[item_name] ~= nil
end

-- called once at startup if the logistc entity prototype list changed
function M.logistic_scan_surfaces()
  local name_filter = {}
  for name, _ in pairs(global.mod.logistic_names) do
    table.insert(name_filter, name)
  end
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered { name = name_filter }
    for _, ent in ipairs(entities) do
      M.logistic_add_entity(ent)
    end
  end
end

function M.get_logistic_entity(unit_number)
  return global.mod.logistic[unit_number]
end

function M.logistic_add_entity(entity)
  if global.mod.logistic[entity.unit_number] == nil then
    global.mod.logistic[entity.unit_number] = entity
    M.queue_insert(entity.unit_number, 0)
    --Queue.push(global.mod.scan_queue, entity.unit_number)
  end
end

function M.logistic_del(unit_number)
  global.mod.logistic[unit_number] = nil
end

function M.logistic_get_list()
  return global.mod.logistic
end

function M.is_vehicle_entity(name)
  return name == "spidertron"
end

function M.vehicle_scan_surfaces()
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered { name = "spidertron" }
    for _, entity in ipairs(entities) do
      M.vehicle_add_entity(entity)
    end
  end
end

function M.get_vehicle_entity(unit_number)
  return global.mod.vehicles[unit_number]
end

-- add a vehicle, assume the caller knows what he is doing
function M.vehicle_add_entity(entity)
  if global.mod.vehicles[entity.unit_number] == nil then
    global.mod.vehicles[entity.unit_number] = entity
    M.queue_insert(entity.unit_number, 0)
    --Queue.push(global.mod.scan_queue, entity.unit_number)
  end
end

function M.vehicle_del(unit_number)
  global.mod.vehicles[unit_number] = nil
end

function M.sensor_add(entity)
  global.mod.sensors[entity.unit_number] = entity
end

function M.sensor_del(unit_number)
  global.mod.sensors[unit_number] = nil
end

function M.sensor_get_list()
  return global.mod.sensors
end

function M.register_chest_entity(entity, requests)
  if requests == nil then
    requests = {}
  end

  if global.mod.chests[entity.unit_number] ~= nil then
    return
  end

  M.queue_insert(entity.unit_number, 0)
  --Queue.push(global.mod.scan_queue, entity.unit_number)
  global.mod.chests[entity.unit_number] = {
    entity = entity,
    requests = requests,
  }

  global.mod.network_chest_has_been_placed = true
end

function M.delete_chest_entity(unit_number)
  global.mod.chests[unit_number] = nil
end

function M.put_inventory_in_network(inv, status)
  status = status or M.UPDATE_STATUS.NOT_UPDATED
  if inv ~= nil then
    local contents = inv.get_contents()
    for item, count in pairs(contents) do
      M.increment_item_count(item, count)
      status = M.UPDATE_STATUS.UPDATED
    end
    inv.clear()
  end
  return status
end

function M.put_chest_contents_in_network(entity)
  M.put_inventory_in_network(entity.get_output_inventory())
end

function M.register_tank_entity(entity, config)
  if global.mod.tanks[entity.unit_number] ~= nil then
    return
  end
  if config == nil then
    config = {
      type = "give",
      limit = 0,
      no_limit = true,
     }
  end

  M.queue_insert(entity.unit_number, 0)
  --Queue.push(global.mod.scan_queue, entity.unit_number)
  global.mod.tanks[entity.unit_number] = {
    entity = entity,
    config = config,
  }
end

function M.delete_tank_entity(unit_number)
  global.mod.tanks[unit_number] = nil
end

function M.put_tank_contents_in_network(entity)
  local fluidbox = entity.fluidbox
  for idx = 1, #fluidbox do
    local fluid = fluidbox[idx]
    if fluid ~= nil then
      M.increment_fluid_count(fluid.name, fluid.temperature, fluid.amount)
    end
  end
  entity.clear_fluid_inside()
end

function M.get_chest_info(unit_number)
  return global.mod.chests[unit_number]
end

function M.get_chests()
  return global.mod.chests
end

function M.get_tank_info(unit_number)
  return global.mod.tanks[unit_number]
end

function M.copy_chest_requests(source_unit_number, dest_unit_number)
  -- REVISIT: creating two chests with the same requests field. Intentional?
  global.mod.chests[dest_unit_number].requests =
    global.mod.chests[source_unit_number].requests
end

function M.copy_tank_config(source_unit_number, dest_unit_number)
  -- REVISIT: creating two tanks with the same config field. Intentional?
  global.mod.tanks[dest_unit_number].config =
    global.mod.tanks[source_unit_number].config
end

function M.set_chest_requests(unit_number, requests)
  local info = M.get_chest_info(unit_number)
  if info == nil then
    return
  end
  global.mod.chests[unit_number].requests = requests
end

function M.get_item_count(item_name)
  return global.mod.items[item_name] or 0
end

function M.get_fluid_count(fluid_name, temp)
  local fluid_temps = global.mod.fluids[fluid_name]
  if fluid_temps == nil then
    return 0
  end
  return fluid_temps[temp] or 0
end

function M.get_items()
  return global.mod.items
end

function M.get_fluids()
  return global.mod.fluids
end

function M.set_item_count(item_name, count)
  if count <= 0 then
    global.mod.items[item_name] = nil
  else
    global.mod.items[item_name] = count
  end
end

function M.set_fluid_count(fluid_name, temp, count)
  if count <= 0 then
    global.mod.fluids[fluid_name][temp] = nil
  else
    local fluid_temps = global.mod.fluids[fluid_name]
    if fluid_temps == nil then
      fluid_temps = {}
      global.mod.fluids[fluid_name] = fluid_temps
    end
    fluid_temps[temp] = count
  end
end

function M.increment_fluid_count(fluid_name, temp, delta)
  local count = M.get_fluid_count(fluid_name, temp)
  M.set_fluid_count(fluid_name, temp, count + delta)
end

function M.increment_item_count(item_name, delta)
  local count = M.get_item_count(item_name)
  global.mod.items[item_name] = count + delta
end

function M.take_item_count(item_name, n_wanted, entity)
  local n_avail = M.get_item_count(item_name)

  local n_trans = math.max(0, math.min(n_avail, n_wanted))
  if n_trans > 0 then
    global.mod.items[item_name] = n_avail - n_trans
  end
  if entity ~= nil and n_trans < n_wanted then
    M.missing_item_set(item_name, n_wanted - n_trans, entity.unit_number)
  end
  return n_trans
end

function M.get_player_info(player_index)
  local info = global.mod.player_info[player_index]
  if info == nil then
    info = {}
    global.mod.player_info[player_index] = info
  end
  return info
end

function M.get_player_info_map()
  return global.mod.player_info
end

function M.get_ui_state(player_index)
  local info = M.get_player_info(player_index)
  if info.ui == nil then
    info.ui = {}
  end
  return info.ui
end

M.UPDATE_STATUS = {
  INVALID        = nil, -- causes the entity to be removed
  UPDATE_PRI_INC  = -1, -- entity needed service
  UPDATE_PRI_SAME = 0,  -- entity needed service
  UPDATE_PRI_DEC  = 1,  -- entity did not need service
  UPDATE_PRI_MAX  = constants.QUEUE_COUNT - 1,
  -- aliases
  UPDATE_BULK     = constants.QUEUE_COUNT - 1,
  UPDATE_LOGISTIC = constants.QUEUE_COUNT - 1,
  UPDATE_VEHICLE  = constants.QUEUE_COUNT - 1,
  NOT_UPDATED     = constants.QUEUE_COUNT - 1,
}

function M.update_queue(update_entity)
  local MAX_ENTITIES_TO_UPDATE = settings.global
    ["item-network-number-of-entities-per-tick"]
    .value
  local updated_entities = {}

  local function inner_update_entity(unit_number)
    if updated_entities[unit_number] ~= nil then
      return M.UPDATE_STATUS.ALREADY_UPDATED
    end
    updated_entities[unit_number] = true

    return update_entity(unit_number)
  end

  for _ = 1, MAX_ENTITIES_TO_UPDATE do
    local unit_number = Queue.pop(global.mod.scan_queue)
    if unit_number == nil then
      break
    end

    local status = inner_update_entity(unit_number)
    if status == M.UPDATE_STATUS.NOT_UPDATED or
       status == M.UPDATE_STATUS.UPDATED or
       status == M.UPDATE_STATUS.ALREADY_UPDATED
    then
      Queue.push(global.mod.scan_queue, unit_number)
    end
  end

  -- finally, swap a random entity to the front of the queue to introduce randomness in update order.
  --Queue.swap_random_to_front(global.mod.scan_queue, global.mod.rand)
end

-- translate a tile name to the item name ("stone-path" => "stone-brick")
function M.resolve_name(name)
  if game.item_prototypes[name] ~= nil or game.fluid_prototypes[name] ~= nil then
    return name
  end

  local prot = game.tile_prototypes[name]
  if prot ~= nil then
    local mp = prot.mineable_properties
    if mp.minable and #mp.products == 1 then
      return mp.products[1].name
    end
  end

  prot = game.entity_prototypes[name]
  if prot ~= nil then
    local mp = prot.mineable_properties
    if mp.minable and #mp.products == 1 then
      return mp.products[1].name
    end
  end

  -- FIXME: figure out how to not hard-code this
  if name == "curved-rail" then
    return "rail", 4
  end
  if name == "straight-rail" then
    return "rail", 1
  end

  clog("Unable to resolve %s", name)
  return nil
end

function M.update_queue_log()
  clog("item-network queue sizes: active: %s  inactive: %s", global.mod.scan_queue.size, global.mod.scan_queue_inactive.size)
end

function M.update_queue_dual(update_entity)
  local MAX_ENTITIES_TO_UPDATE = settings.global
    ["item-network-number-of-entities-per-tick"]
    .value
  local updated_entities = {}

  -- peek the first entry. If we haven't processed it, then pop and return it.
  local function pop_from_q(q)
    local unum = Queue.get_front(q)
    if unum ~= nil and updated_entities[unum] == nil then
      updated_entities[unum] = true
      return Queue.pop(q)
    end
    return nil
  end

  local toggle = true
  for _ = 1, MAX_ENTITIES_TO_UPDATE do
    local unit_number
    if toggle then
      unit_number = pop_from_q(global.mod.scan_queue)
      if unit_number == nil then
        unit_number = pop_from_q(global.mod.scan_queue_inactive)
        if unit_number == nil then
          break
        end
      end
    else
      unit_number = pop_from_q(global.mod.scan_queue_inactive)
      if unit_number == nil then
        unit_number = pop_from_q(global.mod.scan_queue)
        if unit_number == nil then
          break
        end
      end
    end
    toggle = not toggle

    local status = update_entity(unit_number)
    if status == M.UPDATE_STATUS.UPDATED then
      Queue.push(global.mod.scan_queue, unit_number)
    elseif status == M.UPDATE_STATUS.NOT_UPDATED then
      Queue.push(global.mod.scan_queue_inactive, unit_number)
    end
  end
end

function M.update_queue_multi(update_entity)
  local weight_fast = 10
  local weight_med = 6
  local weight_slow = 4
  local MAX_ENTITIES_TO_UPDATE = (weight_fast + weight_med + weight_slow)
  local updated_entities = {}

  local function inner_update_entity(unit_number)
    if updated_entities[unit_number] ~= nil then
      return M.UPDATE_STATUS.ALREADY_UPDATED
    end
    updated_entities[unit_number] = true
    return update_entity(unit_number)
  end

  for _ = 1, MAX_ENTITIES_TO_UPDATE do
    local unit_number
    if weight_slow > 0 then
      weight_slow = weight_slow - 1
      unit_number = Queue.pop(global.mod.scan_queue_slow)
    end
    if unit_number == nil and weight_med > 0 then
      weight_med = weight_med - 1
      unit_number = Queue.pop(global.mod.scan_queue_med)
    end
    if unit_number == nil then
      unit_number = Queue.pop(global.mod.scan_queue_fast)
    end
    if unit_number == nil then
      unit_number = Queue.pop(global.mod.scan_queue_med)
    end
    if unit_number == nil then
      unit_number = Queue.pop(global.mod.scan_queue_slow)
    end
    if unit_number == nil then
      break
    end

    local status = inner_update_entity(unit_number)
    if status == M.UPDATE_STATUS.NOT_UPDATED or
       status == M.UPDATE_STATUS.UPDATED or
       status == M.UPDATE_STATUS.ALREADY_UPDATED
    then
      -- update service_count
      local service_count = global.mod.entity_service_counts[unit_number] or 0
      if status == M.UPDATE_STATUS.NOT_UPDATED then
        service_count = service_count - 1
      elseif status == M.UPDATE_STATUS.UPDATED  then
        service_count = math.max(0, service_count) + 1
      end
      global.mod.entity_service_counts[unit_number] = service_count

      if service_count >= 2 then
        Queue.push(global.mod.scan_queue_fast, unit_number)
      elseif service_count < -60 then
        Queue.push(global.mod.scan_queue_slow, unit_number)
      else
        Queue.push(global.mod.scan_queue_med, unit_number)
      end
    end
  end

  -- finally, swap a random entity to the front of the queue to introduce randomness in update order.
  --Queue.swap_random_to_front(global.mod.scan_queue, global.mod.rand)
end

--[[
  Adds an entity by unit_number and priority.
  0 is the highest priority and will put the entity in the next queue slot.
  The largest value (lowest priority) is (constants.QUEUE_COUNT - 1).
  That will put the entity in the previous queue slot.
]]
function M.queue_insert(unit_number, priority)
  -- clamp priority to 0 .. QUEUE_COUNT-2
  priority = math.max(0, math.min(priority, constants.QUEUE_COUNT - 2))
  -- save the priority for next time
  global.mod.entity_priority[unit_number] = priority

  -- q_idx is where to put it, Priority 0 => scan_index + 1
  -- scan_index is 1-based, so we subtract 1 and then add 1 (scan_index - 1 + 1 + priority)
  local q_idx = 1 + (global.mod.scan_index + priority) % constants.QUEUE_COUNT
  Queue.push(global.mod.scan_queues[q_idx], unit_number)

  --print(string.format("[%s] ADD  q %s unum %s si=%s p=%s qx=%s", game.tick, q_idx, unit_number, global.mod.scan_index, priority, constants.QUEUE_COUNT))
end

--[[
This processes up to "item-network-number-of-entities-per-tick" entities from the active queue.
If the current queue is empty and the deadline has passed then we step to the next queue, which
is processed on the next tick.

The function is passed in to avoid circular dependencies.
]]
function M.update_queue_lists(update_entity)
  local MAX_ENTITIES_TO_UPDATE = settings.global
    ["item-network-number-of-entities-per-tick"]
    .value

  local qs = global.mod.scan_queues
  local q_idx = global.mod.scan_index
  if q_idx < 1 or q_idx > #qs then
    q_idx = 1
  end
  local q = qs[q_idx]

  for _ = 1, MAX_ENTITIES_TO_UPDATE do
    local unit_number = Queue.pop(q)
    if unit_number == nil then
      -- nothing to process in this queue. step to the next one if past the deadline
      if game.tick >= (global.mod.scan_deadline or 0) then
        global.mod.scan_deadline = game.tick + constants.QUEUE_TICKS
        global.mod.scan_index = q_idx + 1
        --print(string.format("[%s] NEXT scan_idx=%s", game.tick, global.mod.scan_index))
      end
      return
    end
    --print(string.format("[%s] PROC q %s unum %s", game.tick, q_idx, unit_number))

    -- the UPDATE_STATUS are actually relative priorities.
    local old_pri = global.mod.entity_priority[unit_number] or 0
    local pri_adj = update_entity(unit_number, old_pri)
    -- nil means entity is invalid.
    if pri_adj ~= nil then
      M.queue_insert(unit_number, old_pri + pri_adj)
    else
      clog("Dropped: G unum %s", unit_number)
    end
  end
end

M.update_queue = M.update_queue_lists

function M.log_entity(title, entity)
  if entity ~= nil then
    if entity.name == "entity-ghost" or entity.name == "tile-ghost" then
      clog("%s: [%s] GHOST %s @ (%s,%s)",
        title, entity.unit_number, entity.ghost_name, entity.position.x, entity.position.y)
    else
      clog("%s: [%s] %s @ (%s,%s)",
        title, entity.unit_number, entity.name, entity.position.x, entity.position.y)
    end
  end
end

--[[
Automatically configure a chest to request ingredients needed for linked assemblers.
        local buffer_size = settings.global
          ["item-network-stack-size-on-assembler-paste"].value

]]
function M.auto_network_chest(entity)
  local requests = {}
  local provides = {}

  --local buffer_size = settings.global["item-network-stack-size-on-assembler-paste"].value

  M.log_entity("*** auto-scan", entity)

  -- scan surroundings for inserters, loaders, and mining drills. long-handed inserter can be 2 away
  local entities = entity.surface.find_entities_filtered{ position=entity.position, radius=3,
      type={"inserter", "loader", "mining-drill" }}

  clog(" ++ found %s entities", #entities)

  -- NOTE: is seems like the inserter doesn't set pickup_target or drop_target until it needs to
--[[
  local function log_entities_at(title, pos, exclude_ent)
    local nn = entity.surface.find_entities_filtered{ position=pos, radius=0.1 }
    for _, ent in ipairs(nn) do
      if ent ~= exclude_ent then
        M.log_entity(title, ent)
      end
    end
  end
]]
  for idx, ent in ipairs(entities) do
    if ent.unit_number ~= nil then
      if ent.drop_target == entity then
        M.log_entity(string.format("%s is drop_target:", idx), ent)
        clog(" entity name=%s type=%s", ent.name, ent.type)
      else
        M.log_entity(string.format("%s NOT drop_target:", idx), ent)
        clog(" entity name=%s type=%s", ent.name, ent.type)
      end
    end
    --[[
    M.log_entity("auto-check", ent)
    game.print(string.format("  pick=(%s,%s) drop=(%s,%s)",
      ent.pickup_position.x, ent.pickup_position.y,
      ent.drop_position.x, ent.drop_position.y))
    log_entities_at(" - pick", ent.pickup_position, ent)
    log_entities_at(" - drop", ent.drop_position, ent)
    M.log_entity("auto-check-pick", ent.pickup_target)
    M.log_entity("auto-check-drop", ent.drop_target)

    -- pickup from the chest, delivering elsewhere. scan target recipe for 'ingredients'
    if ent.pickup_target == entity then
      if ent.drop_target ~= nil then
        if ent.drop_target.type == "assembling-machine" then
          local recipe = ent.drop_target.get_recipe()
          if recipe ~= nil then
            for _, xx in ipairs(recipe.ingredients) do
              -- We don't actually care about the ingredient count, as the inserter can only hold so
              -- many and the chest should be refilled before the inserter is finished.
              -- and it will be auto-adjusted
              requests[xx.name] = (requests[xx.name] or 0) + buffer_size
            end
          end
        end

        -- REVISIT: other types? furnace? at least we can add coal
      end
    end

    -- drop in the chest, pick up from elsewhere. scan target recipe for 'products'
    if ent.drop_target == entity then
      if ent.pickup_target ~= nil then
        if ent.pickup_target.type == "assembling-machine" then
          local recipe = ent.pickup_target.get_recipe()
          if recipe ~= nil then
            for _, xx in ipairs(recipe.products) do
              provides[xx.name] = xx.amount + (provides[xx.name] or 0)
            end
          end
        end

        -- REVISIT: other types? furnace?
      end
    end
  ]]
  end

  -- REVISIT: do we need to scan for loaders?
  return requests, provides
end

return M
