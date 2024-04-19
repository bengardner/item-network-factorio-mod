--[[
Services the spidertron.
REVISIT: NOT doing ammo right now. Top off existing ammo?
]]
local GlobalState = require "src.GlobalState"
local inv_utils = require("src.inv_utils")

local function service_spidertron(info)
  local entity = info.entity
  if entity.vehicle_logistic_requests_enabled then
    local inv_trash = entity.get_inventory(defines.inventory.spider_trash)
    local inv_trunk = entity.get_inventory(defines.inventory.spider_trunk)

    GlobalState.put_inventory_in_network(inv_trash)
    inv_utils.inventory_handle_requests(entity, inv_trunk)
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

GlobalState.register_service_task("spidertron", {
  service=service_spidertron
})
