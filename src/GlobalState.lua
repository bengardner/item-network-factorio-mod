local Queue = require "src.Queue"
local tables_have_same_keys = require("src.tables_have_same_keys")
  .tables_have_same_keys
local constants = require "src.constants"
local clog = require("src.log_console").log
local Event = require('__stdlib__/stdlib/event/event')

local M = {}

M.get_default_limit = require("src.DefaultLimits").get_default_limit

local setup_has_run = false

function M.setup()
  if setup_has_run then
    return
  end
  setup_has_run = true

  -- clog("*** ietm-network SETUP ***")
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


  global.mod.entity_info = {} -- key=unit_number, val=table
  entity_info contents:
    {
      entity = LuaEntity,             -- reference to the entity (which may not be valid anymore)
      service_type = "network-chest", -- service type used in a service look-up table
      service_tick = 111,             -- last tick when this was serviced
      service_delta = 222,            -- tick delta at last service
      service_priority = 5,           -- priority at the last service
      -- the rest depend on the type
      requests = { ... },             -- chest requests
      recent_items = { ... },         -- recent items for auto-provider chest
      config = { ... },               -- network-tank config
      contents = { ... },             -- last get_contents() result for logistic Storage chest
    }
 ]]

--[[
This is called once at startup/load.
It should set up the global data structure.
]]
function M.inner_setup()
  -- always rebuild the ammo and fuel tables (for now)
  global.ammo_table = nil
  global.fuel_table = nil

  -- the 'mod' table holds most interesting data
  if global.mod == nil then
    global.mod = {
      rand = game.create_random_generator(),
      items = {},
      item_limits = {}
    }
  end

  -- create the table for entity_info
  if global.mod.entity_info == nil then
    -- random info that is automatically removed when the entity is destroyed
    global.mod.entity_info = {} -- key=unit_number, val=table
  end

  -- reset the service queue if the size changes or this is the first call
  if global.mod.scan_queues == nil or (#global.mod.scan_queues ~= constants.QUEUE_COUNT) then
    M.reset_queues()
  end
  -- M.log_queue_info()

  -- remove any player UIs, as those really shouldn't be saved
  M.remove_old_ui()
  if global.mod.player_info == nil then
    global.mod.player_info = {}
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

  if global.mod.logistic_names ~= nil then
    global.mod.logistic_names = nil -- clean up
  end

  -- scan prototypes to see if we need to rescan all surfaces
  local name_service_map = M.scan_prototypes()
  if true or not tables_have_same_keys(name_service_map, global.name_service_map) then
    clog("*** PROTOTYPES CHANGED ***")
    global.name_service_map = name_service_map
    M.scan_surfaces()
  end

  -- major upgrade to unified entity info table, trashes all the separate tables
  if global.mod.chests ~= nil then
    M.convert_to_entity_info()
  end

  if global.mod.alert_trans == nil then
    global.mod.alert_trans = {} -- alert_trans[unit_number] = game.tick
  end

  if global.mod.sensors == nil then
    global.mod.sensors = {}
  end
end

--[[
Creates a new entity from an entity and tags table.
Calls the create() method for the entity.
That ends up calling M.entity_info_add().
]]
local function generic_create_entity(entity, info)
  if entity ~= nil and entity.valid then
    local service_type = M.get_service_type_for_entity(entity.name)
    if service_type == nil then
      --clog("created unhandled %s [%s] %s", entity.name, entity.type, entity.unit_number)
      return
    end

    clog("generic_add [%s] => %s", entity.name, serpent.line(service_type))
    if type(service_type.create) == "function" then
      service_type.create(entity, info or {})
    else
      clog("ERROR: no create for %s", entity.name)
    end
  end
end

--[[
Converts the previous data style to one unified entity_info table.
]]
function M.convert_to_entity_info()
  --[[
      {
      entity = LuaEntity,             -- reference to the entity (which may not be valid anymore)
      service_type = "network-chest", -- service type used in a service look-up table (required)
      service_tick = 111,             -- last tick when this was serviced (auto)
      service_delta = 222,            -- tick delta at last service (auto)
      service_priority = 5,           -- priority at the last service (auto)
      -- the rest depend on the type
      requests = { ... },             -- chest requests
      recent_items = { ... },         -- recent items for auto-provider chest
      config = { ... },               -- network-tank config
      contents = { ... },             -- last get_contents() result for logistic Storage chest
    }
  ]]

  global.name_service_map = M.scan_prototypes()

  -- chests need a 'service_type' field
  for unum, info in pairs(global.mod.chests or {}) do
    if info.entity ~= nil and info.entity.valid then
      generic_create_entity(info.entity, info)
    end
  end
  global.mod.chests = nil

  -- tanks need a 'service_type' field
  for unum, info in pairs(global.mod.tanks or {}) do
    if info.entity ~= nil and info.entity.valid then
      generic_create_entity(info.entity, info)
    end
  end
  global.mod.tanks = nil

  -- vehicles was misnamed, as it only handles the spidertron
  for unum, ent in pairs(global.mod.vehicles or {}) do
    generic_create_entity(ent)
  end
  global.mod.vehicles = nil

  for unum, ent in pairs(global.mod.logistic or {}) do
    generic_create_entity(ent)
  end
  global.mod.logistic = nil

  for unum, ent in pairs(global.mod.serviced or {}) do
    generic_create_entity(ent)
  end
  global.mod.serviced = nil

  M.scan_surfaces()
end

function M.reset_queues()
  print("item-network: RESET SCAN QUEUE")
  global.mod.scan_deadline = 0 -- keep doing nothing until past this tick
  global.mod.scan_index = 1 -- working on the queue in this index

  global.mod.scan_queues = {} -- list of queues to process
  for idx = 1, constants.QUEUE_COUNT do
    -- key=unit_number, val=priority
    global.mod.scan_queues[idx] = {}
  end

  -- add all entities, spreading them evenly
  local pri = 0
  for unum, info in pairs(global.mod.entity_info) do
    local entity = info.entity
    if entity ~= nil and entity.valid then
      if M.get_service_type_for_entity(entity.name) ~= nil then
        info.service_priority = pri
        M.queue_insert(unum, info)
        pri = pri + 1
        if pri > constants.QUEUE_COUNT - 2 then
          pri = 0
        end
      end
    end
  end
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

-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------

function M.rand_hex(len)
  local chars = {}
  for _ = 1, len do
    table.insert(chars, string.format("%x", math.floor(global.mod.rand() * 16)))
  end
  return table.concat(chars, "")
end

-------------------------------------------------------------------------------

function M.entity_info_get(unit_number)
  return global.mod.entity_info[unit_number]
end

-- grab and filter
function M.entity_info_get_type(unit_number, service_type)
  local info = global.mod.entity_info[unit_number]
  if info ~= nil and info.service_type == service_type then
    return info
  end
end

function M.entity_info_set(unit_number, info)
  info.unit_number = unit_number
  global.mod.entity_info[unit_number] = info
end

function M.entity_info_clear(unit_number)
  global.mod.entity_info[unit_number] = nil
end

-- handles adding a new entity for nearly all types.
function M.entity_info_add(entity, tags)
  if entity == nil or not entity.valid then
    return
  end
  local unit_number = entity.unit_number
  if unit_number == nil then
    return
  end
  local service_type = M.get_service_type_for_entity(entity.name)
  if service_type == nil then
    return
  end
-- only if we haven't already added this one
  local info = M.entity_info_get(unit_number)
  if info == nil then
    -- grab the service_type. bail if not handled.

    info = {
      service_type = service_type,
      entity = entity,
    }

    local svc_func = M.get_service_task(service_type)
    if svc_func == nil then
      clog("genric : nothing for %s", serpent.line(info))
    end
    if svc_func ~= nil and svc_func.tag ~= nil then
      if tags ~= nil then
        info[svc_func.tag] = tags[svc_func.tag] or {}
      end
    end
    M.entity_info_set(unit_number, info)
    M.queue_insert(unit_number, info)
  else
    if info.service_type ~= service_type then
      clog("changed service type on %s from %s to %s", entity.name, info.service_type, service_type)
      info.service_type = service_type
    end
  end
  return info
end

-------------------------------------------------------------------------------
-- Sensors are NOT treated the same as other entities.

function M.sensor_add(entity)
  global.mod.sensors[entity.unit_number] = entity
end

function M.sensor_del(unit_number)
  global.mod.sensors[unit_number] = nil
end

function M.sensor_get_list()
  return global.mod.sensors
end

-------------------------------------------------------------------------------

function M.register_chest_entity(entity, requests)
  M.entity_info_add(entity, { requests = requests or {} })
end

--[[
Move items from inv to the network, if possible.
Respects limits. A bit slower than items_inv_to_net().
]]
function M.items_inv_to_net_with_limits(inv)
  if inv ~= nil then
    local contents = inv.get_contents()
    for item, count in pairs(contents) do
      local n_trans = math.min(M.get_insert_count(item), count)
      if n_trans > 0 then
        local n_moved = inv.remove({ name=item, count=n_trans })
        if n_moved > 0 then
          M.increment_item_count(item, n_moved)
        end
      end
    end
  end
end

--[[
Move items from inv to the network. No limit checks.
]]
function M.items_inv_to_net(inv)
  if inv ~= nil then
    local contents = inv.get_contents()
    for item, count in pairs(contents) do
      M.increment_item_count(item, count)
    end
    inv.clear()
  end
end
M.put_inventory_in_network = M.items_inv_to_net

function M.put_chest_contents_in_network(entity)
  M.put_inventory_in_network(entity.get_output_inventory())
end

-------------------------------------------------------------------------------

function M.register_tank_entity(entity, config)
  M.entity_info_add(entity, { config=config or { type="auto" } })
end

function M.delete_tank_entity(unit_number)
  M.entity_info_clear(unit_number)
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

function M.put_contents_in_network(entity)
  -- drain any fluid
  local fluidbox = entity.fluidbox
  for idx = 1, #fluidbox do
    local fluid = fluidbox[idx]
    if fluid ~= nil then
      M.increment_fluid_count(fluid.name, fluid.temperature, fluid.amount)
    end
  end
  entity.clear_fluid_inside()

  -- return any inventory
  for idx = 1, entity.get_max_inventory_index() do
    M.put_inventory_in_network(entity.get_output_inventory(idx))
  end
end


-- grab the entity info and ensure that it is
function M.get_chest_info(unit_number)
  return M.entity_info_get_type(unit_number, "network-chest")
end

function M.get_tank_info(unit_number)
  local info = M.entity_info_get(unit_number)
  if info ~= nil and constants.NETWORK_TANK_NAMES[info.service_type] ~= nil then
    return info
  end
end

function M.copy_chest_requests(source_unit_number, dest_unit_number)
  local src_info = M.get_chest_info(source_unit_number)
  local dst_info = M.get_chest_info(dest_unit_number)
  if src_info ~= nil and dst_info ~= nil then
    dst_info.requests = table.deepcopy(src_info.requests)
  end
end

function M.copy_tank_config(source_unit_number, dest_unit_number)
  local src_info = M.get_tank_info(source_unit_number)
  local dst_info = M.get_tank_info(dest_unit_number)
  if src_info ~= nil and dst_info ~= nil then
    dst_info.config = table.deepcopy(src_info.config)
  end
end

function M.set_chest_requests(unit_number, requests)
  local info = M.get_chest_info(unit_number)
  if info == nil then
    return
  end
  info.requests = requests
end

-------------------------------------------------------------------------------

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
  UPDATE_PRI_SAME = 0,  -- entity needed service, but current pri is OK
  UPDATE_PRI_DEC  = 1,  -- entity did not need service
  UPDATE_PRI_MAX  = constants.QUEUE_COUNT - 1,
  -- aliases
  UPDATE_BULK     = constants.QUEUE_COUNT - 1,
  UPDATE_LOGISTIC = constants.QUEUE_COUNT - 1,
  UPDATE_VEHICLE  = constants.QUEUE_COUNT - 1,
  NOT_UPDATED     = constants.QUEUE_COUNT - 1,
}

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

-------------------------------------------------------------------------------

M.service_tasks = {}

--[[
Register a service task.

@service_type is the name to register.
@funcs is a table that provides the service info.

@funcs.service(info) -- required
  Does whatever needs to be done to service the entity.

@funcs.create(entity, tags) -- optional
  This should do whatever needs to be done to create the data for the entity
  and then call GlobalState.entity_info_add(entity, tags).
  The default is to just call GlobalState.entity_info_add(entity, tags).
  If funcs.tag is defined, entity_info_add() will copy that from tags.
    info[funcs.tag] = tags[funcs.tag]
  The default is usually good enough.

@funcs.clone(dst_info, src_info) -- optional
  Copy the required data from src_info to dst_info.
  This is called to handler pasting between same-name entities.
  If funcs.tag is set, then the default is to do a table.deepcopy().
     dst_info[funcs.tag] = table.deepcopy(src_info[funcs.tag])

@funcs.tag
  The name of the member that holds the configuration table.

@funcs.paste(dst_info, src_entity) -- optional
  Handles pasting from src_entity to dst_info.
  This is only called if clone() was not defined or the entities have different names.
  This handles stuff like pasting a assembler to a chest.
]]
function M.register_service_task(service_type, funcs)
  -- "service" is required or what is the point?
  if funcs == nil or funcs.service == nil then
    assert(false, string.format("register_service_task: incorrect usage %s", serpent.line(funcs)))
  end
  -- entity_info_add() suffices for just about everything
  if funcs.create == nil then
    funcs.create = M.entity_info_add
  end
  M.service_tasks[service_type] = funcs
  clog("added service %s", service_type)
  for k, v in pairs(funcs) do
    clog('  - %s : %s', k, type(v))
  end
end

function M.get_service_task(service_type)
  local retval = M.service_tasks[service_type or ""]
  if retval == nil then
    clog("get_service_task: nothing for %s", service_type)
  end
  return retval
end

function M.get_service_type_for_entity(name)
  if global.name_service_map == nil then
    error("called before init: get_service_type_for_entity")
  end
  return global.name_service_map[name]
end

--[[
  Adds an entity by unit_number and priority.
  0 is the highest priority and will put the entity in the next queue slot.
  The largest value (lowest priority) is (constants.QUEUE_COUNT - 1).
  That will put the entity in the previous queue slot.
  Uses (info.service_priority or 0) as the priority.
]]
function M.queue_insert(unit_number, info)
  -- clamp priority to 0..QUEUE_COUNT-2 (inclusive)
  local priority = math.max(0, math.min(info.service_priority or 0, constants.QUEUE_COUNT - 2))

  -- q_idx is where to put it, Priority 0 => scan_index + 1
  -- scan_index is 1-based, so we subtract 1 and then add 1 (scan_index - 1 + 1 + priority)
  local q_idx = 1 + (global.mod.scan_index + priority) % constants.QUEUE_COUNT
  global.mod.scan_queues[q_idx][unit_number] = info
  --print(string.format("[%s] ADD  q %s unum %s si=%s p=%s qx=%s", game.tick, q_idx, unit_number, global.mod.scan_index, priority, constants.QUEUE_COUNT))

  info.service_priority = priority
end

--[[
Remove unit_number from all queues.
Should only be used when re-scanning and NOT resetting queues.
]]
function M.queue_remove(unit_number)
  if unit_number ~= nil then
    for _, qq in ipairs(global.mod.scan_queues) do
      qq[unit_number] = nil
    end
  end
end

--[[
This processes up to "item-network-number-of-entities-per-tick" entities from the active queue.
If the current queue is empty and the deadline has passed then we step to the next queue, which
is processed on the next tick.

The function is passed in to avoid circular dependencies.
]]
function M.queue_service()
  local MAX_ENTITIES_TO_UPDATE = settings.global
    ["item-network-number-of-entities-per-tick"]
    .value

  local qs = global.mod.scan_queues
  local q_idx = global.mod.scan_index or 1
  if q_idx < 1 or q_idx > #qs then
    q_idx = 1
    global.mod.scan_index = q_idx
    if global.mod.scan_queue_start_tick ~= nil then
      local dt = game.tick - global.mod.scan_queue_start_tick
      --clog("queue complete in %.1f sec (%s ticks)", dt / 60, dt)
    end
    global.mod.scan_queue_start_tick = game.tick
  end
  local q = qs[q_idx]

  for _ = 1, MAX_ENTITIES_TO_UPDATE do
    local unit_number, info = next(q)
    if unit_number == nil then
      -- nothing to process in this queue. step to the next one if past the deadline
      if game.tick >= (global.mod.scan_deadline or 0) then
        global.mod.scan_deadline = game.tick + constants.QUEUE_TICKS
        global.mod.scan_index = q_idx + 1
        --print(string.format("[%s] NEXT scan_idx=%s", game.tick, global.mod.scan_index))
      end
      return
    end
    -- remove from the active queue
    q[unit_number] = nil
    --print(string.format("[%s] PROC q %s unum=%s pri=%s", game.tick, q_idx, unit_number, old_pri))

    if type(info) == "number" then
      local pri = info
      info = M.entity_info_get(unit_number)
      if info ~= nil then
        info.service_priority = pri
      end
    end

    if info ~= nil and info.entity ~= nil and info.entity.valid then
      if global.name_service_map[info.entity.name] == nil then
        clog("NOTE: no longer processing [%s] - dropped", info.entity.name)

      elseif info.entity.to_be_deconstructed() then
        -- we don't remove or servive to-be-deconstructed entities
        info.service_priority = M.UPDATE_STATUS.NOT_UPDATED
        M.queue_insert(unit_number, info)

      else
        -- Would be really nice to cache this lookup, but can't store functions in save file.
        local func = M.get_service_task(info.service_type)
        if func == nil then
          clog("service: nothing for %s", serpent.line(info))
        end
        if func ~= nil and func.service ~= nil then
          -- the UPDATE_STATUS values are relative priorities.
          local pri_adj = func.service(info)
          if pri_adj ~= nil then
            if info.service_tick ~= nil then
              info.service_tick_delta = game.tick - info.service_tick
            end
            info.service_tick = game.tick

            info.service_priority = (info.service_priority or 0) + pri_adj
            M.queue_insert(unit_number, info)
          end
        else
          clog("WARNING: no handler for [%s] - dropped", serpent.line(info))
          for k, _ in pairs(M.service_tasks) do
            clog("avail: %s", k)
          end
        end
      end
    end
  end
end

-- grab the priority for the entity from the service queues
function M.get_priority(unit_number)
  for _, qq in ipairs(global.mod.scan_queues) do
    local pri = qq[unit_number]
    if pri ~= nil then
      return pri
    end
  end
end

-- create a histogram of priorities
function M.get_priority_histogram()
  local h = {} -- key=pri, val=count
  for _, qq in ipairs(global.mod.scan_queues) do
    for _, pri in pairs(qq) do
      h[pri] = (h[pri] or 0) + 1
    end
  end
  return h
end

function M.log_queue_info()
  local h = M.get_priority_histogram()
  clog("priority hist: %s", serpent.line(h))

  local qs = global.mod.scan_queues
  local cnt = 0
  for idx = 1, #qs do
    local ts = table_size(qs[idx])
    clog("queue %s: size=%s", idx, ts)
    cnt = cnt + ts
  end
  clog("total %s", cnt)
end

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

function M.get_fuel_table()
  if global.fuel_table == nil then
    local fuels = {} -- array { name=name, val=energy per stack, cat=category }
      for _, prot in pairs(game.item_prototypes) do
        local fc = prot.fuel_category
        if fc ~= nil then
          table.insert(fuels, { name=prot.name, val=prot.stack_size * prot.fuel_value, cat=fc })
        end
      end
    table.sort(fuels, function (a, b) return a.val > b.val end)

    print(string.format("fuel table: %s", serpent.line(fuels)))
    global.fuel_table = fuels
  end
  return global.fuel_table
end

function M.get_best_available_fuel(entity)
  --clog("called get best fuel on %s", entity.name)
  local bprot = entity.prototype.burner_prototype
  if bprot ~= nil then
    local fct = bprot.fuel_categories
    --clog("  fuel cat: %s", serpent.line(fct))
    local ff = M.get_fuel_table()
    --clog("  fuel tab: %s", serpent.line(ff))
    for _, fuel in ipairs(ff) do
      if fct[fuel.cat] ~= nil then
        local n_avail = M.get_item_count(fuel.name)
        if n_avail > 0 then
          --clog("FUEL: %s can use %s and we have %s", entity.name, fuel.name, n_avail)
          return fuel.name, n_avail
        end
        --clog("FUEL: %s can use %s, but we are out", entity.name, fuel.name)
      end
    end
  end
  return nil
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

--[[
Collect a decreasing list of ammos byte damage / type.
]]
function M.get_ammo_table()
  if global.ammo_table == nil then
    local ammo_list = {}
    for _, prot in pairs(game.item_prototypes) do
      if prot.type == "ammo" then
        local at = prot.get_ammo_type()
        if at ~= nil then
          local damage = recurse_find_damage(at.action)
          if damage ~= nil and type(damage.amount) == "number" then
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
    for k, xx in pairs(ammo_list) do
      table.sort(xx, function (a, b) return a.amount > b.amount end)
    end

    -- reduce to a list of names
    local ammo_table = {}
    for cat, xxx in pairs(ammo_list) do
      local aa = {}
      ammo_table[cat] = aa
      for _, row in ipairs(xxx) do
        table.insert(aa, row.name)
      end
    end

    -- hard code some projectile stuff that I haven't figured out how to detect
    ammo_table['cannon-shell'] = {
      "explosive-uranium-cannon-shell",
      "explosive-cannon-shell",
      "cannon-shell"
    }

    ammo_table['flamethrower'] = { "flamethrower-ammo" }

    ammo_table['artillery-shell'] = { "artillery-shell" }

    print(string.format("ammo table: %s", serpent.line(ammo_table)))
    global.ammo_table = ammo_table
  end
  return global.ammo_table
end

--[[
Grab the best ammo for the category.
@category is typically one of "bullet", "rocket", "flamethrower", etc
]]
function M.get_best_available_ammo(category)
  -- haven't figured out a good way to do anything other than bullets
  local ammo_list = M.get_ammo_table()[category]
  if ammo_list ~= nil then
    for _, ammo_name in ipairs(ammo_list) do
      local n_avail = M.get_item_count(ammo_name)
      if n_avail > 0 then
        -- clog("AMMO: %s can use %s and we have %s", category, ammo_name, n_avail)
        return ammo_name, n_avail
      end
      -- clog("AMMO: %s can use %s, but we are out", category, ammo_name)
    end
  else
    clog("no ammo list for cat %s", category)
  end
end

function M.last_service_set(unit_number)
  global.mod.last_service[unit_number] = game.tick
end

function M.last_service_get(unit_number)
  return global.mod.last_service[unit_number] or 0
end

function M.last_service_clear(unit_number)
  global.mod.last_service[unit_number] = nil
end

-------------------------------------------------------------------------------

function M.scan_prototypes()
  clog("item-network: scanning prototypes")

   -- key=entity_name, val=service_type
  local name_to_service = {
    -- add built-in stuff that we create
    ["network-chest"]           = "network-chest",
    ["network-chest-provider"]  = "network-chest-provider",
    ["network-chest-requester"] = "network-chest-requester",
    ["network-tank"]            = "network-tank",
    ["network-tank-provider"]   = "network-tank-provider",
    ["network-tank-requester"]  = "network-tank-requester",
  }

  -- key=type, val=service_type
  local type_to_service = {
    ["spider-vehicle"]     = "spidertron",
    ["car"]                = "general-service", -- "car",
    ["furnace"]            = "furnace", -- "furnace",
    ["ammo-turret"]        = "general-service", -- "ammo-turret",
    ["artillery-turret"]   = "general-service", -- "artillery-turret",
  }

  if settings.global["item-network-service-assemblers"].value then
    clog("Adding 'assembling-machine' to the list")
    type_to_service["assembling-machine"] = "general-service" -- "assembling-machine"
  end

  for _, prot in pairs(game.entity_prototypes) do
    if prot.type == "logistic-container" then
      --if prot.logistic_mode == "requester" or prot.logistic_mode == "buffer" or prot.logistic_mode == "storage" then
      name_to_service[prot.name] = "logistic-chest-" .. prot.logistic_mode
      --elseif prot.logistic_mode == "active-provider" then
      --  name_to_service[prot.name] = "logistic-chest-provider"
      --else
      --  clog("logistic_mode: %s %s", prot.logistic_mode, prot.name)
      --end
    else
      local ss = type_to_service[prot.type]
      if ss ~= nil then
        name_to_service[prot.name] = ss
      else
        -- check for other 'general-service'
        local svc_type
        if prot.has_flag("player-creation") then
          -- check for stuff that burns chemicals (coal)
          if prot.burner_prototype ~= nil and prot.burner_prototype.fuel_categories.chemical == true then
            svc_type = "general-service" -- for refueling
            --clog("Adding %s based on burner_prototype", prot.name)
          end
        end
        if svc_type ~= nil then
          name_to_service[prot.name] = svc_type
        end
      end
    end
  end
  return name_to_service
end

-- called once at startup if scan_prototypes() returns something different
function M.scan_surfaces()
  clog("[%s] item-network: Scanning surfaces", game.tick)
  local name_filter = {}
  for name, _ in pairs(global.name_service_map) do
    table.insert(name_filter, name)
  end
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered { name = name_filter }
    for _, ent in ipairs(entities) do
      M.entity_info_add(ent)
    end
  end
  M.reset_queues()
  clog("[%s] item-network: Scanning complete", game.tick)
end

-------------------------------------------------------------------------------

-- not sure this belongs here...
Event.on_configuration_changed(function ()
  clog("item-network: *** CONFIGURATION CHANGED ***")
  -- need to rescan the fuel table
  global.ammo_table = nil
  global.fuel_table = nil
end)

-- need to run as soon as 'game' is available
Event.on_nth_tick(1, M.setup)
--Event.on_init(M.setup)

return M
