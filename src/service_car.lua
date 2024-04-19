--[[
Service handler for the type "car".
]]
local GlobalState = require "src.GlobalState"
local string = require('__stdlib__/stdlib/utils/string')
local ServiceEntity = require("src.ServiceEntity")

local M = {}

function M.car_service(info)
  local entity = info.entity

  ServiceEntity.refuel_entity(entity)

  ServiceEntity.service_reload_ammo_car(entity,
    entity.get_inventory(defines.inventory.car_ammo))

  if info.car_output_inv == true then
    GlobalState.items_inv_to_net_with_limits(entity.get_output_inventory())
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

function M.car_create(entity, tags)
  local info = GlobalState.entity_info_add(entity, tags)

  -- Set a flag if the car should discard the inventory to the net.
  -- This is currently for one special case.
  if string.starts_with(entity.name, "vehicle-miner") then
    info.car_output_inv = true
  end
end

GlobalState.register_service_task("car", {
  create=M.car_create,
  service=M.car_service
})

return M
