--[[
Services entities of type 'lab'.
]]
local GlobalState = require "src.GlobalState"
local inv_utils = require("src.inv_utils")
local ServiceEntity = require("src.ServiceEntity")

local M = {}

function M.lab_service(info)
  local entity = info.entity
  local status = entity.status
  local pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC

  -- handle refueling (burner lab)
  ServiceEntity.refuel_entity(entity)

  local inv = entity.get_inventory(defines.inventory.lab_input)
  if inv == nil then
    return
  end

  -- TODO: do the timing stuff like is done for assemblers/recipes
  -- labs are usually slow, but there are some really fast ones out there (SE)

  for _, item in ipairs(entity.prototype.lab_inputs) do
    -- TODO: check if we can produce the input to avoid 'missing' indication for
    -- stuff we can't make yet.
    inv_utils.transfer_item_to_inv_level(entity, inv, item, 10)
  end

  if status ~= entity.status then --  defines.entity_status.missing_science_packs
    print(string.format("lab status changed %s to %s", status, entity.status))
  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

GlobalState.register_service_task("lab", {
  service=M.lab_service
})

return M
