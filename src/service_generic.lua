--[[
Generic entity handler.
]]
local GlobalState = require "src.GlobalState"
local ServiceEntity = require("src.ServiceEntity")
local clog = require("src.log_console").log

local M = {}

-- this never changes
local artillery_ammo_cats = { "artillery-shell" }

--[[
  Updates the entity.
  @reutrn GlobalState.UPDATE_STATUS.INVALID or GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
]]
function M.generic_service(info)
  local entity = info.entity

  local isz = entity.get_max_inventory_index()
  if isz < 1 then
    --FIXME: this alerts to a coding error, remove when stable
    clog("No inventory for %s", entity.name)
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  ServiceEntity.refuel_entity(entity)

  if entity.type == "ammo-turret" then
    ServiceEntity.service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.turret_ammo), entity.prototype.attack_parameters.ammo_categories)

  elseif entity.type == "artillery-turret" then
    ServiceEntity.service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.artillery_turret_ammo), artillery_ammo_cats)

  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

--[[
  Updates the entity.
  @reutrn GlobalState.UPDATE_STATUS.INVALID or GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
]]
function M.ammo_turret(info)
  local entity = info.entity

  ServiceEntity.service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.turret_ammo), entity.prototype.attack_parameters.ammo_categories)

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

function M.artillery_turret(info)
  local entity = info.entity

  ServiceEntity.service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.artillery_turret_ammo), artillery_ammo_cats)

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

GlobalState.register_service_task("general-service", {
  service=M.generic_service
})
GlobalState.register_service_task("ammo-turret", {
  service=M.ammo_turret
})
GlobalState.register_service_task("artillery-turret", {
  service=M.artillery_turret
})

return M
