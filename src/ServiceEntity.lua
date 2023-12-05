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
      elseif n_added < n_trans then
        -- there was insufficient available
        GlobalState.missing_item_set(name, entity.unit_number, n_trans - n_added)
      end
    else
      -- there was nothiing available
      GlobalState.missing_item_set(name, entity.unit_number, count)
    end
  end
end

local function transfer_item_to_inv_max(entity, inv, name)
  transfer_item_to_inv(entity, inv, name, inv.get_insertable_count(name))
end

local fuel_list = {
  --"processed-fuel",
  "coal",
  "wood",
}

local function service_refuel(entity, inv)
  if inv.is_empty() then
    local fuel_name, n_avail = GlobalState.get_best_available_fuel(entity)
    if fuel_name == nil then
      return
    end
    --clog("best fuel for %s is %s and we have %s", entity.name, fuel_name, n_avail)
    local prot = game.item_prototypes[fuel_name]
    --local n_avail = GlobalState.get_item_count(fuel_name)
    if n_avail > 0 then
      local n_add = (#inv * prot.stack_size) -- - 12
      transfer_item_to_inv(entity, inv, fuel_name, math.min(n_avail, n_add))
    end
    return
    --[[
    for _, fuel_name in ipairs(fuel_list) do
      local prot = game.item_prototypes[fuel_name]
      local n_avail = GlobalState.get_item_count(fuel_name)
      if prot ~= nil and n_avail > 0 then
        -- add some if if empty
        -- need to NOT fill it to the top or we can cause a deadlock
        local n_add = (#inv * prot.stack_size) - 12
        transfer_item_to_inv(entity, inv, fuel_name, math.min(n_avail, n_add))
        return
      end
    end
    ]]
  else
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
          n_have = inv.get_item_count(ing.name)
          if n_have < ing.amount then
            GlobalState.missing_item_set(ing.name, entity.unit_number, ing.amount - n_have)
          end
        end
      end
    end
  end
end

-- TODO: search this on startup. categories: "artillery-shell", "cannon-shell", "flamethrower", "rocket", "shotgun-shell"
-- "ammo" category "bullet"
local ammo_bullet_types = {
  "uranium-rounds-magazine",   -- damage 24
  "piercing-rounds-magazine",  -- damage @ ammo_type.action.action_delivery.target_effects[]/type="damage" .damage.amount=8
  "firearm-magazine",          -- damage 5
}

-- "ammo" category "artillery-shell"
local ammo_artillery_shell_types = {
  "artillery-shell",
}

local function service_reload_ammo_type(entity, inv, ammo_category)
  if inv == nil then
    clog("service_reload_ammo_type: %s nil inv", entity.name)
    return
  end

  if inv.is_empty() then
    local best_ammo = GlobalState.get_best_available_ammo(ammo_category)
    clog("service_reload_ammo_type: %s inv empty, cat=%s best=%s", entity.name, ammo_category, best_ammo)
    if best_ammo ~= nil then
      transfer_item_to_inv_max(entity, inv, best_ammo)
      return
    end
  else
    for name, count in pairs(inv.get_contents()) do
      transfer_item_to_inv_max(entity, inv, name)
    end
  end
end

local function service_reload_ammo_car(entity, inv)
  if inv == nil then
    return
  end
  -- sanity check: no guns means no ammo
  local prot = entity.prototype
  if prot.guns == nil then
    clog("weird. no guns on %s", entity.name)
    return
  end
  local inv_cat = {}
  -- figure out the ammo categories for each inventory slot
  -- REVISIT: this is only needed if the inventory slot is empty
  -- direct: prot.indexed_guns[idx].attack_parameters.ammo_categories[1]
  -- TODO: remember this at runtime, as it can't change
  for _, ig in pairs(prot.indexed_guns) do
    local ac = ig.attack_parameters.ammo_categories
    table.insert(inv_cat, ac[1])
  end

  for idx = 1, #inv do
    local stack = inv[idx]
    if stack.valid_for_read and stack.count > 0 then
      -- top off the ammo
      transfer_item_to_inv_max(entity, inv, stack.name)
    else
      -- empty: find good ammo to add
      local ammo_name = GlobalState.get_best_available_ammo(inv_cat[idx])
      if ammo_name ~= nil then
        transfer_item_to_inv_max(entity, inv, ammo_name)
      end
    end
  end
end

--[[
  Updates the entity.
  @reutrn GlobalState.UPDATE_STATUS.INVALID or GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
]]
function M.update_entity(info)
  local entity = info.entity

  local isz = entity.get_max_inventory_index()
  if isz < 1 then
    clog("No inventory for %s", entity.name)
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
    --return GlobalState.UPDATE_STATUS.INVALID
  end

  -- handle refueling
  local f_inv = entity.get_fuel_inventory()
  if f_inv ~= nil then
    service_refuel(entity, f_inv)
  end

  if entity.type == "furnace" then
    GlobalState.items_inv_to_net_with_limits(entity.get_output_inventory())

    -- add ore to match the previous recipe
    local inv_src = entity.get_inventory(defines.inventory.furnace_source)
    if inv_src ~= nil and inv_src.get_item_count() < 10 then
      service_recipe_inv(entity, entity.get_inventory(defines.inventory.furnace_source), entity.previous_recipe, 50)
    end

  elseif entity.type == "assembling-machine" then
    --clog("Service [%s] %s status=%s", entity.unit_number, entity.name, entity.status)
    local old_status = entity.status

    -- move output items to net
    local out_inv = entity.get_output_inventory()
    GlobalState.items_inv_to_net_with_limits(out_inv)

    local inp_inv = entity.get_inventory(defines.inventory.assembling_machine_input)

    -- was full and still can't send off items, so shut off, return inputs
    if not out_inv.is_empty() and old_status == defines.entity_status.full_output then
      -- full output, no room in net,
      GlobalState.items_inv_to_net(inp_inv)
    else
      service_recipe_inv(entity, inp_inv, entity.get_recipe(), 2)
    end
    -- will stop refill if status becomes "output full"
  elseif entity.type == "car" then
    service_reload_ammo_car(entity, entity.get_inventory(defines.inventory.car_ammo), ammo_bullet_types)

  elseif entity.type == "ammo-turret" then
    service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.turret_ammo), "bullet")

  elseif entity.type == "artillery-turret" then
    service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.artillery_turret_ammo), "artillery-shell")

  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

function M.create(entity, tags)
  GlobalState.service_add_entity(entity)
end

GlobalState.register_service_task("general-service", { create=M.create, service=M.update_entity })

return M
