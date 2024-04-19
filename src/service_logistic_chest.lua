--[[
Services all logistic chests.
]]
local GlobalState = require "src.GlobalState"
local tabutils = require("src.tables_have_same_keys")
local ServiceEntity = require("src.ServiceEntity")
local inv_utils = require("src.inv_utils")
local clog = require("src.log_console").log

-------------------------------------------------------------------------------

-- handles logistic storage chests
local function service_logistic_chest_storage(info)
  -- clog("[%s] storage [%s] %s", game.tick, info.entity.unit_number, info.entity.name)
  if not settings.global["item-network-service-logistic-chest"].value then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  local entity = info.entity
  local inv = entity.get_output_inventory()
  local new_contents = inv.get_contents()
  if next(new_contents) ~= nil then
    if info.contents == nil then
      info.contents = new_contents
      info.contents_tick = game.tick
      return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
    end
    -- clog("storage [%s] has %s", info.entity.unit_number, serpent.line(new_contents))

    if tabutils.tables_have_same_counts(new_contents, info.contents) then
      local tick_delta = game.tick - (info.contents_tick or game.tick)
      -- drop content after it does not change for 1 minute
      if tick_delta > 60*60 then
        -- send contents to network
        GlobalState.put_inventory_in_network(inv)
        --clog("[%s] [%s] storage to network: %s", game.tick, entity.unit_number, serpent.line(new_contents))
        info.contents = {} -- assume it was sent
        info.contents_tick = game.tick
      end
    else
      -- changed, so reset the timer
      info.contents = new_contents
      info.contents_tick = game.tick
      --clog("[%s] [%s] storage updated: %s", game.tick, entity.unit_number, serpent.line(new_contents))
    end
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

-- handles logistic buffer and requester chests
local function service_logistic_chest_requester(info)
  if settings.global["item-network-service-logistic-chest"].value then
    local entity = info.entity
    inv_utils.inventory_handle_requests(entity, entity.get_output_inventory())
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

local function service_logistic_chest_active_provider(info)
  if settings.global["item-network-service-logistic-chest"].value then
    return ServiceEntity.update_network_chest_provider(info)
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

local function service_logistic_chest_passive_provider(info)
  if settings.global["item-network-service-logistic-chest"].value then
    GlobalState.items_inv_to_net_with_limits(info.entity.get_output_inventory())
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

-------------------------------------------------------------------------------

GlobalState.register_service_task("logistic-chest-requester", {
  service=service_logistic_chest_requester
})
GlobalState.register_service_task("logistic-chest-buffer", {
  service=service_logistic_chest_requester
})
GlobalState.register_service_task("logistic-chest-storage", {
  service=service_logistic_chest_storage
})
GlobalState.register_service_task("logistic-chest-active-provider", {
  service=service_logistic_chest_active_provider
})
GlobalState.register_service_task("logistic-chest-passive-provider", {
  service=service_logistic_chest_passive_provider
})
