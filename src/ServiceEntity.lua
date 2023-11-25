--[[
  Handles the misc entities that are not network chests, tanks, or sensors.
  - type "furnace"
    - name "steel-furnace"
    - name "stone-furnace"
  - type "assembling-machine"
    - name "assembling-machine-1"
    - name "assembling-machine-2"
    - name "assembling-machine-3"
    - name "centrifuge"
    - name "chemical-plant"
  - type 'mining-drill'
    - name "burner-mining-drill"
]]
local GlobalState = require "src.GlobalState"
local clog = require("src.log_console").log

local M = {}

--[[
Transfer items from the network to the inventory.
  @entity - for logging
  @inv - the inventory to full
  @name - the item name
  @count - the number of items to add
]]
local function transfer_item_to_inv(entity, inv, name, count)
  if count > 0 then
    local n_avail = GlobalState.get_item_count(name)
    local n_trans = math.min(n_avail, count)
    if n_trans > 0 then
      local n_added = inv.insert{ name=name, count=n_trans }
      if n_added > 0 then
        GlobalState.increment_item_count(name, -n_added)
        --clog("[%s] %s : added %s %s", entity.unit_number, entity.name, name, n_added)
      end
    end
  end
end

local function service_refuel(entity)
  -- we only do coal for now
  local fuel_name = "coal"
  local prot = game.item_prototypes[fuel_name]

  local inv = entity.get_fuel_inventory()
  if inv ~= nil then
    -- add coal if empty
    if inv.is_empty() then
      -- need to NOT fill it to the top or we can cause a deadlock
      transfer_item_to_inv(entity, inv, fuel_name, (#inv * prot.stack_size) - 12)
      return
    end

    -- try to top off the fuel(s)
    for fuel, _ in ipairs(inv.get_contents()) do
      local fuel_prot = game.item_prototypes[fuel]
      if fuel_prot ~= nil then
        local n_need = inv.get_insertable_count(fuel) - 12
        -- start requesting when fuel is below 1/2 stack
        if n_need > fuel_prot.stack_size / 2 then
          transfer_item_to_inv(entity, inv, fuel, n_need)
        end
      end
    end
  end
end

local function service_recipe_inv(entity, inv, recipe, factor)
  if recipe ~= nil and inv ~= nil then
    local contents = inv.get_contents()
    for _, ing in pairs(recipe.ingredients) do
      local prot = game.item_prototypes[ing.name]
      if prot ~= nil then
        local n_have = contents[ing.name] or 0
        local n_need = math.max(ing.amount, math.max(ing.amount * factor, prot.stack_size))
        if n_have < n_need then
          transfer_item_to_inv(entity, inv, ing.name, n_need - n_have)
        end
      end
    end
  end
end

--[[
  Updates the entity.
  @reutrn GlobalState.UPDATE_STATUS.INVALID or GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
]]
function M.update_entity(entity)
  if not entity.valid then
    return GlobalState.UPDATE_STATUS.INVALID
  end
  -- 'to_be_deconstructed()' may be temporary
  if entity.to_be_deconstructed() then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  if entity.type == "furnace" then
    GlobalState.items_inv_to_net_with_limits(entity.get_output_inventory())
    service_refuel(entity)

    -- add ore to match the previous recipe
    local inv_src = entity.get_inventory(defines.inventory.furnace_source)
    if inv_src ~= nil and inv_src.get_item_count() < 10 then
      service_recipe_inv(entity, entity.get_inventory(defines.inventory.furnace_source), entity.previous_recipe, 50)
    end

  elseif entity.type == "mining-drill" then
    -- mining drills dump their output directly to a network chest, so we just need to refuel
    service_refuel(entity)

  elseif entity.type == "assembling-machine" then
    --clog("Service [%s] %s status=%s", entity.unit_number, entity.name, entity.status)
    if entity.status == defines.entity_status.item_ingredient_shortage then
      service_recipe_inv(entity, entity.get_inventory(defines.inventory.assembling_machine_input), entity.get_recipe(), 2)
    end
    GlobalState.items_inv_to_net_with_limits(entity.get_output_inventory())
    -- will stop refill if status becomes "output full"

  elseif entity.name == "boiler" then
    service_refuel(entity)

  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

return M
