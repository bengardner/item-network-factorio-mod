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
  if game.item_prototypes[name] ~= nil then
    transfer_item_to_inv(entity, inv, name, inv.get_insertable_count(name))
  end
end

local function transfer_item_to_inv_level(entity, inv, name, count)
  if game.item_prototypes[name] ~= nil then
    local n_have = inv.get_item_count(name)
    if n_have < count then
      local n_ins = math.min(inv.get_insertable_count(name), count - n_have)
      if n_ins > 0 then
        transfer_item_to_inv(entity, inv, name, n_ins)
      end
    end
  end
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

-- this never changes
local artillery_ammo_cats = { "artillery-shell" }

local function service_reload_ammo_type(entity, inv, ammo_categories)
  -- check inputs that might be bad
  if inv == nil or ammo_categories == nil or #ammo_categories == 0 then
    return
  end

  if inv.is_empty() then
    -- add ammo
    for _, cat in ipairs(ammo_categories) do
      local best_ammo = GlobalState.get_best_available_ammo(cat)
      -- clog("service_reload_ammo_type: %s inv empty, cat=%s best=%s", entity.name, ammo_category, best_ammo)
      if best_ammo ~= nil then
        transfer_item_to_inv_max(entity, inv, best_ammo)
        -- it is remotely possible that there can be multiple ammo_categories...
        --return
      end
    end
  else
    -- top off existing ammo
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
    service_reload_ammo_car(entity, entity.get_inventory(defines.inventory.car_ammo))

    if info.car_output_inv == true then
      GlobalState.items_inv_to_net_with_limits(entity.get_output_inventory())
    end

  elseif entity.type == "ammo-turret" then
    service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.turret_ammo), entity.prototype.attack_parameters.ammo_categories)

  elseif entity.type == "artillery-turret" then
    service_reload_ammo_type(entity, entity.get_inventory(defines.inventory.artillery_turret_ammo), artillery_ammo_cats)

  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

-- determine the ore based on the inputs, last_recipe or info.ore_name
function M.furnace_get_ore(info)
  local entity = info.entity
  local src_inv = entity.get_inventory(defines.inventory.furnace_source)

  -- check input inventory (ore)
  for item, _ in pairs(src_inv.get_contents()) do
    info.ore_name = item
    return item
  end

  -- check previous recipe (check output)
  local recipe = entity.previous_recipe
  if recipe ~= nil then
    for _, ing in ipairs(recipe.ingredients) do
      info.ore_name = ing.name
      return ing.name
    end
  end

  -- go with whatever was last configured (inputs and outputs are empty)
  return info.ore_name
end

function M.furnace_update(info)
  local entity = info.entity

  M.refuel_entity(entity)

  local o_inv = entity.get_output_inventory()
  local inv_src = entity.get_inventory(defines.inventory.furnace_source)

  -- grab the configured ore and the input ore
  local old_ore = info.ore_name
  local ore_name = M.furnace_get_ore(info)

  -- forcibly remove output if the ore changed
  if ore_name ~= old_ore then
    GlobalState.items_inv_to_net(o_inv)

  elseif not o_inv.is_empty() then

    -- force-dump the output if the ore isn't an ingredient to the output item
    local name = next(o_inv.get_contents())
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

      if ore_ok then
        -- remove output with limits
        GlobalState.items_inv_to_net_with_limits(o_inv)
      else
        -- force dump on ore change
        GlobalState.items_inv_to_net(o_inv)
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
  -- we only handle same-type pasting (furnace to furnace).
  local dest = dst_info.entity
  if dest.type ~= source.type then
    return
  end

  -- we have to know about the source
  local src_info = GlobalState.entity_info_get(source.unit_number)
  if src_info == nil then
    -- clog("paste: no source info")
    return
  end

  -- determine the ore -- the furnace may not have been serviced since placing ore
  local ore_name = M.furnace_get_ore(src_info)
  if ore_name == nil or dst_info.ore_name == ore_name then
    return
  end

  -- ore_name changed: update the ore_name in the dest
  dst_info.ore_name = ore_name

  -- clog("paste: ore=%s", serpent.line(dst_info.ore_name))

  -- force-dump existing ingredients and output
  local dst_ing_inv = dest.get_inventory(defines.inventory.furnace_source)
  GlobalState.items_inv_to_net(dst_ing_inv)
  GlobalState.items_inv_to_net(dest.get_output_inventory())

  -- max out the input ore
  transfer_item_to_inv_max(dest, dst_ing_inv, ore_name)

  -- NOTE: if the furnace was smelting something, we will have to
  -- purge that from the service routine.
end

local function furnace_clone(dst_info, src_info)
  -- We want to fill the furnace immediately, so hook into paste without
  -- changing dst_info.ore_name first
  furnace_paste(dst_info, src_info.entity)
end

local function furnace_refresh_tags(info)
  if info.ore_name == nil then
    info.ore_name = M.furnace_get_ore(info)
  end
  return info.ore_name
end

-------------------------------------------------------------------------------

function M.lab_service(info)
  local entity = info.entity

  -- handle refueling (burner lab)
  M.refuel_entity(entity)

  local inv = entity.get_inventory(defines.inventory.lab_input)
  if inv == nil then
    return
  end

  -- REVISIT: load the minimum?
  for _, item in ipairs(entity.prototype.lab_inputs) do
    transfer_item_to_inv_level(entity, inv, item, 10)
  end

  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end


-------------------------------------------------------------------------------

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
  refresh_tags=furnace_refresh_tags,
  clone=furnace_clone,
  tag="ore_name",
})
GlobalState.register_service_task("lab", { create=M.create, service=M.lab_service })

return M
