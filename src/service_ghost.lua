--[[
Handles the entity-ghost, building as needed.
]]
local GlobalState = require "src.GlobalState"
local clog = require("src.log_console").log

local M = {}

local function populate_ghost(entity, is_entity)
  local ghost_prototype = entity.ghost_prototype
  if ghost_prototype == nil then
    return -- need a ghost prototype
  end

  -- check to see if we have enough items in the network
  local item_list = ghost_prototype.items_to_place_this
  local missing = false
  for _, ing in ipairs(item_list) do
    local cnt = GlobalState.get_item_count(ing.name)
    if cnt < ing.count then
      GlobalState.missing_item_set(ing.name, entity.unit_number, ing.count - cnt)
      missing = true
    end
  end
  if missing then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  local surface = entity.surface
  local bbox = entity.bounding_box
  local _, revived_entity, __ = entity.revive{raise_revive = true}
  if revived_entity ~= nil then
    for _, ing in ipairs(item_list) do
      GlobalState.increment_item_count(ing.name, -ing.count)
    end
    return -- entity is now invalid, as service_entity was created
  end

  local retval = GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  if is_entity then
    local ents = surface.find_entities_filtered({ area=bbox, to_be_deconstructed=true })
    local to_mine = {}
    for _, eee in ipairs(ents) do
      if eee.prototype.mineable_properties.minable then
        table.insert(to_mine, eee)
      else
        if eee.type == 'cliff' then
          GlobalState.cliff_queue(eee)
        else
          GlobalState.mine_queue(eee)
        end
      end
    end

    if #to_mine > 0 then
      local inv = game.create_inventory(16)
      for _, eee in ipairs(to_mine) do
        eee.mine({ inventory=inv })
        retval = 0
      end
      for name, count in pairs(inv.get_contents()) do
        GlobalState.increment_item_count(name, count)
      end
      inv.destroy()
    end
  end

  -- failed: likely blocked by a cliff, try again later
  return retval
end

function M.entity_ghost_service(info)
  return populate_ghost(info.entity, true)
end

function M.tile_ghost_service(info)
  return populate_ghost(info.entity, false)
end

GlobalState.register_service_task("entity-ghost", { service=M.entity_ghost_service })
GlobalState.register_service_task("tile-ghost", { service=M.tile_ghost_service })

return M
