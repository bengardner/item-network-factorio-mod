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
local string = require('__stdlib__/stdlib/utils/string')

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
    local n_avail = GlobalState.get_item_count(fuel_name)
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

function M.refuel_entity(entity)
  local f_inv = entity.get_fuel_inventory()
  if f_inv ~= nil then
    service_refuel(entity, f_inv)
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
    -- clog("service_reload_ammo_type: %s nil inv", entity.name)
    return
  end

  if inv.is_empty() then
    local best_ammo = GlobalState.get_best_available_ammo(ammo_category)
    -- clog("service_reload_ammo_type: %s inv empty, cat=%s best=%s", entity.name, ammo_category, best_ammo)
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
  M.refuel_entity(entity)

  if entity.type == "assembling-machine" then
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

    if info.car_output_inv == true then
      GlobalState.items_inv_to_net_with_limits(entity.get_output_inventory())
    end

  elseif entity.type == "ammo-turret" then
    service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.turret_ammo), "bullet")

  elseif entity.type == "artillery-turret" then
    service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.artillery_turret_ammo), "artillery-shell")

  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

function M.furnace_update(info)
  local entity = info.entity

  M.refuel_entity(entity)

  local o_inv = entity.get_output_inventory()
  local inv_src = entity.get_inventory(defines.inventory.furnace_source)

  -- add input ore
  local ore_name = info.ore_name
  for item, _ in pairs(inv_src.get_contents()) do
    ore_name = item
    break
  end
  if info.ore_name ~= ore_name then
    -- forcibly remove output, as the input changed
    GlobalState.items_inv_to_net(o_inv)
    info.ore_name = ore_name
  else
    -- remove output with limits
    GlobalState.items_inv_to_net_with_limits(o_inv)
    if not o_inv.is_empty() then
      local name = next(o_inv.get_contents())
      -- clog("[%s][%s @ %s] not empty after output clear: %s ore=%s",
      --   entity.unit_number, entity.name, serpent.line(entity.position), name, ore_name)
      if name ~= nil then
        local ore_ok = false
        -- output is full. Force clear if ore_name is not an ingredient
        local recipe = game.recipe_prototypes[name]
        if recipe ~= nil then
          -- clog("ing %s", serpent.line(recipe.ingredients))

          for _, ing in ipairs(recipe.ingredients) do
            if ing.name == ore_name then
              ore_ok = true
            end
          end
        end
        if not ore_ok then
          -- clog("force-dump on recipe change")
          GlobalState.items_inv_to_net(o_inv)
        end
      end
    end
  end

  if info.ore_name ~= nil then
    transfer_item_to_inv_max(entity, inv_src, info.ore_name)
  end
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

local function print_smelting_recipes(force)
  for name, recipe in pairs(force.recipes) do
    if "smelting" == recipe.category then
      clog("recipe %s : c=%s i=%s p=%s", name, recipe.category, serpent.line(recipe.ingredients), serpent.line(recipe.products))
    end
  end
end

--[[
Make furnces do 'auto mode'.
 - if empty, pick any recipe that has a shortage?
 - if output is full AND the network hit the limit, then switch

Assumption:
  - one input -> one output
  - recipe named after the output

Can store the recipe ingredient name in the info (info.ore_name).
'paste' will copy the ore_name and then remove output/source (if different) and load source
the recipe is checked on service.
  - if input ore is are available
    - compare info.ore_name against input
    - if not the same
      - update info.ore_name
      - clear output
  - top off fuel
  - top off ore with current ore_name
]]

local function furnace_paste(dst_info, source)
  --[[
  When pasting, we can only go off of the inventory in the source.
  ]]
  local dest = dst_info.entity
  if dest.type == "furnace" and source.type == "furnace" then
    local src_inv = source.get_inventory(defines.inventory.furnace_source)
    local ore_name

    -- grab ore_name from the source contents
    for name, _ in pairs(src_inv.get_contents()) do
      ore_name = name
      break
    end

    -- OK. try grabbing ore_name from the source info
    if ore_name == nil then
      local src_info = GlobalState.entity_info_get(source.unit_number)
      if src_info ~= nil then
        ore_name = src_info.ore_name
      end
    end

    if ore_name == nil or dst_info.ore_name == ore_name then
      return
    end

    --clog("paste[%s @ %s][%s] changed ore from %s to %s",
    --  dest.name, serpent.line(dest.position), dest.unit_number,
    --  serpent.line(dst_info.ore_name), ore_name)
    dst_info.ore_name = ore_name

    -- clear out the input and output inventories
    local dst_ing_inv = dest.get_inventory(defines.inventory.furnace_source)
    GlobalState.items_inv_to_net(dst_ing_inv)
    GlobalState.items_inv_to_net(dest.get_output_inventory())

    -- add some ore to lock in the change
    --local ss = game.item_prototypes[ore_name].stack_size
    transfer_item_to_inv_max(dest, dst_ing_inv, ore_name)
    -- NOTE: there may still be something smelting. handle that later.
  end
end

local function furnace_clone(dst_info, src_info)
  -- We want to fill the furnace immediately, so hook into paste without
  -- changing dst_info.ore_name first
  furnace_paste(dst_info, src_info.entity)
end

function M.create(entity, tags)
  local info = GlobalState.entity_info_add(entity, tags)

  -- set a flag if the car should discard the inventory to the net.
  if entity.type == 'car' and string.starts_with(entity.name, "vehicle-miner") then
    info.car_output_inv = true
  end
end

GlobalState.register_service_task("general-service", { create=M.create, service=M.update_entity })
GlobalState.register_service_task("furnace", {
  create=M.create,
  service=M.furnace_update,
  paste=furnace_paste,
  clone=furnace_clone,
  tag="ore_name",
})

return M
