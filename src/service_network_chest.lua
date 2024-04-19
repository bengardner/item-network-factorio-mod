--[[
Services network chests.
]]
local GlobalState = require "src.GlobalState"
local tabutils = require("src.tables_have_same_keys")
local ServiceEntity = require("src.ServiceEntity")
local clog = require("src.log_console").log

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
        status = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
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
    status = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
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
  local status = GlobalState.UPDATE_STATUS.UPDATE_BULK

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
        status = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
        count = count - n_transfer
      end
      if count > 0 then
        -- Since there is one slot per item, count will be <= stack_size.
        leftovers[item] = count
      end
    end
  end

  -- check if the list of locked items changed
  if tabutils.tables_have_same_keys(info.locked_items, leftovers) then
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

  return status
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
  if inv.supports_filters() then
    for _ = 1, count do
      inv.set_filter(inv_idx, item)
      inv_idx = inv_idx + 1
    end
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

  returns GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME or GlobalState.UPDATE_STATUS.UPDATE_PRI_INC or GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC
]]
local function update_network_chest_configured_common(info, inv, contents)
  local status = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
  local locked_items = {} -- key=item, val=true

  -- pass 1: Send excessive items; note which sends fail in "locked" table
  -- does not affect the priority
  for item, n_have in pairs(contents) do
    local n_want, r_type = get_request_buffer(info.requests, item)

    -- try to send to the network if we have too many
    local n_extra = n_have - n_want
    if n_extra > 0 then
      local n_free = GlobalState.get_insert_count(item)
      local n_transfer = math.min(n_extra, n_free)
      if n_transfer > 0 then
        -- status = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
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
  local added_some = false
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
            added_some = true
            contents[req.item] = n_have + n_transfer
            GlobalState.set_item_count(req.item, n_innet - n_transfer)

            --[[ If we filled the entire buffer, then we may not be requesting often enough.
            If there is enough in the net for another 4*buffer, then we are probably not
            requesting enough. Up the buffer size by 1.
            ]]
            if n_transfer == n_want then
              --clog('chest increasing request freq pri=%s', info.service_priority)
              status = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
              --if info.service_priority < 2 and n_innet > n_transfer * 4 then
              if n_innet > n_transfer * 4 then
                req.buffer = req.buffer + 1
                --clog('chest increasing request buffer =%s', req.buffer)
              end
            end
          end
        else
          GlobalState.missing_item_set(req.item, info.entity.unit_number, n_want - n_have)
        end
      end
    end
  end

  -- update less frequently if we didn't request anything
  if added_some == false then
    status = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC
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

  -- just locked, so update less often
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
end

--[[
Process a configured, locked chest.
]]
local function update_network_chest_configured_locked(info, inv, contents)
  local status, locked_items = update_network_chest_configured_common(info, inv, contents)

  -- check if the list of locked items changed
  if tabutils.tables_have_same_keys(info.locked_items, locked_items) then
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

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
end

-- this is the handler for the "old" network-chest
local function service_network_chest(info)
  local inv = info.entity.get_output_inventory()
  local contents = inv.get_contents()

  -- make sure recent_items is present (can get cleared elsewhere)
  if info.recent_items == nil then
    info.recent_items = {}
  end

  local is_locked = (inv.get_bar() < #inv)
  if #info.requests == 0 then
    -- fully automatic provider
    if is_locked then
      update_network_chest_unconfigured_locked(info, inv, contents)
    else
      update_network_chest_unconfigured_unlocked(info, inv, contents)
    end
    return GlobalState.UPDATE_STATUS.UPDATE_BULK
  else -- configured
    if is_locked then
      return update_network_chest_configured_locked(info, inv, contents)
    else
      return update_network_chest_configured_unlocked(info, inv, contents)
    end
  end
end

--[[
This is the handler for the "new" requester-only chest.
Fills the chest with one item (filter slot 1), respecting the bar.

This chest is not USED RIGHT NOW
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
            status = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
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

local function service_network_chest_provider(info)
  -- TODO: adjust priority. increase if was full and now empty. decrease otherwise.
  return ServiceEntity.update_network_chest_provider(info)
end

local function service_network_chest_requester(info)
  -- TODO: adjust priority. increase if was empty and now full. decrease otherwise. adjust request amount if pri==0.
  update_network_chest_requester(info)
  return GlobalState.UPDATE_STATUS.UPDATE_BULK
end

local function create_network_chest(entity, tags)
  local requests = {}

  if tags ~= nil then
    local requests_tag = tags.requests
    if requests_tag ~= nil then
      requests = requests_tag
    end
  end

  GlobalState.register_chest_entity(entity, requests)
end

-- copy the settings from @src_info to @dst_info (same entity name)
local function clone_network_chest(dst_info, src_info)
  dst_info.requests = table.deepcopy(src_info.requests)
end

-- paste the settings from @source onto dst_info
local function paste_network_chest(dst_info, source)
  if source.name == "network-chest" then
    local src_info = GlobalState.get_chest_info(source.unit_number)
    if src_info ~= nil then
      dst_info.requests = table.deepcopy(src_info.requests)
    end

  elseif source.type == "assembling-machine" or source.type == "rocket-silo" then
    -- anything with a recipe
    local recipe = source.get_recipe()
    if recipe ~= nil then
      local requests = {}
      local buffer_size = settings.global
        ["item-network-chest-size-on-paste"].value
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
      dst_info.requests = requests
    end

  elseif source.type == "container" then
    -- Turn filter slots into requests, if any. Works for 'se-rocket-launch-pad'
    local inv = source.get_output_inventory()
    if inv.is_filtered() then
      -- clog("SOURCE: %s t=%s inv slots=%s filt=%s", source.name, source.type, #inv, inv.is_filtered())
      local requests = {}
      local buffer_size = settings.global["item-network-chest-size-on-paste"].value or 5
      for idx=1,#inv do
        local ff = inv.get_filter(idx)
        if ff ~= nil then
          local prot = game.item_prototypes[ff]
          if prot ~= nil then
            local stack_size = prot.stack_size
            local buffer = math.min(buffer_size, stack_size)
            table.insert(requests, {
              type = "take",
              item = ff,
              buffer = buffer,
              limit = 0,
            })
            -- clog(" - [%s] %s", idx, ff, serpent.line(requests[#requests]))
          end
        end
      end
      -- don't change anything if there were no filtered slots
      if next(requests) ~= nil then
        dst_info.requests = requests
      end
    end
  end
end

-------------------------------------------------------------------------------
-- register entity handlers

GlobalState.register_service_task("network-chest", {
  service=service_network_chest,
  create=create_network_chest,
  paste=paste_network_chest,
  clone=clone_network_chest,
  tag="requests",
})

-- provider has no extra data, filters or bar.
GlobalState.register_service_task("network-chest-provider", {
  service=service_network_chest_provider,
  create=create_network_chest,
})

GlobalState.register_service_task("network-chest-requester", {
  service=service_network_chest_requester,
  create=create_network_chest,
  paste=paste_network_chest,
  clone=clone_network_chest,
  tag="requests",
})
