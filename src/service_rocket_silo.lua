--[[
Services the type "rocket-silo".
Populates the recipe ingredients and removes output items.
We don't add a satellite or payload, as there are many options.
]]
local GlobalState = require "src.GlobalState"
local ServiceEntity = require("src.ServiceEntity")

local M = {}

-- service the rocket silo, which is essentially the same as an assembling machine.
-- do not attempt to put a satellite in the rocket
function M.service_rocket_silo(info)
  local entity = info.entity
  local pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC
  local status = entity.status -- item_ingredient_shortage

  --print(string.format("%s: status=%s [%s] pri=%s", entity.name, entity.status, status_str(entity.status), info.service_priority))
  -- don't change priority while waiting for launch
  if status ~= defines.entity_status.working then
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
  end

  local out_inv = entity.get_output_inventory()
  if out_inv ~= nil then
    GlobalState.items_inv_to_net_with_limits(out_inv)
  end

  local recipe = entity.get_recipe()
  local inp_inv = entity.get_inventory(defines.inventory.assembling_machine_input)

  if recipe ~= nil and inp_inv ~= nil then
    -- ingredients automatically adjusts to service period
    local is_short = ServiceEntity.service_recipe_inv(info, entity, inp_inv, recipe)

    -- if we were short AND we were out of ingredients, then increase pri
    if status == defines.entity_status.item_ingredient_shortage and not is_short then
      pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
    end
  end

  return pri
end

GlobalState.register_service_task("rocket-silo", {
  service=M.service_rocket_silo
})

return M
