--[[
Some basic inventory transfer utilities.
]]
local GlobalState = require "src.GlobalState"

local M = {}

--[[
Transfer items from the network to the inventory.
  @entity - for logging and force
  @inv - the inventory to fill
  @name - the item name
  @count - the number of items to add

Returns the number of items transferred.
]]
function M.transfer_item_to_inv(entity, inv, name, count)
  local n_added = 0
  if count > 0 then
    local n_avail = GlobalState.get_item_count(name)
    local n_trans = math.min(n_avail, count)
    if n_trans > 0 then
      n_added = inv.insert{ name=name, count=n_trans }
      if n_added > 0 then
        GlobalState.increment_item_count(name, -n_added)
      else
        -- there was insufficient available
        GlobalState.missing_item_set(name, entity.unit_number, n_trans)
      end
    else
      -- there was nothiing available
      GlobalState.missing_item_set(name, entity.unit_number, count)
    end
  end
  return n_added
end

--[[
Transfer the maximum number of items to the inventory.
  @entity - for logging and force
  @inv - the inventory to fill
  @name - the item name
]]
function M.transfer_item_to_inv_max(entity, inv, name)
  if game.item_prototypes[name] ~= nil then
    M.transfer_item_to_inv(entity, inv, name, inv.get_insertable_count(name))
  end
end

--[[
Transfer items to the inventory to bring the count up to @count.
  @entity - for logging and force
  @inv - the inventory to fill
  @name - the item name
  @count - the desired final count of the item in the inventory
]]
function M.transfer_item_to_inv_level(entity, inv, name, count)
  if game.item_prototypes[name] ~= nil then
    local n_have = inv.get_item_count(name)
    if n_have < count then
      local n_ins = math.min(inv.get_insertable_count(name), count - n_have)
      if n_ins > 0 then
        M.transfer_item_to_inv(entity, inv, name, n_ins)
      end
    end
  end
end

-- fulfill requests. entity must have request_slot_count and get_request_slot()
-- useful for vehicles (spidertron) and logistic containers
function M.inventory_handle_requests(entity, inv)
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
          end
        end
        if n_transfer < n_wanted then
          GlobalState.missing_item_set(req.name, entity.unit_number, n_wanted - n_transfer)
        end
      end
    end
  end

  -- logsitics are always at the back of the list
  return GlobalState.UPDATE_STATUS.UPDATE_LOGISTIC
end

return M
