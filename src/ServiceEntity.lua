--[[
Functions to assist in servicing entities.
]]
local GlobalState = require "src.GlobalState"
local inv_utils = require("src.inv_utils")
local clog = require("src.log_console").log

local M = {}

--[[
Add fuel to an empty inventory.
Look up the 'best' fuel and add that.
returns whether fuel was added.
]]
local function service_refuel_empty(entity, inv)
  local fuel_name, n_avail = GlobalState.get_best_available_fuel(entity)
  if fuel_name == nil or n_avail == nil then
    return false
  end
  --sclog("best fuel for %s is %s and we have %s", entity.name, fuel_name, n_avail)
  if n_avail > 0 then
    local prot = game.item_prototypes[fuel_name]
    local n_add = (#inv * prot.stack_size) -- - 12
    return inv_utils.transfer_item_to_inv(entity, inv, fuel_name, math.min(n_avail, n_add)) > 0
  end
  return false
end

--[[
Add fuel to the entity.

If empty, we pick the best available fuel and add that.
 - preferred
 - not blocked

 If non-empty, we check to make sure the current fuel is not blocked.
 If blocked, we remove it.
 If not preferred and we have the preferred fuel, then remove the fuel.

Ideally, the amount of fuel would be enough for 3 * service period ticks.

returns whether fuel was added.
]]
function M.service_refuel(entity, inv)
  local cfg = GlobalState.fuel_config_get(entity.name)
  local preferred = cfg.preferred

  -- See if we need to purge non-preferred fuel
  local purge = false
  if preferred ~= nil then
    local n_avail = GlobalState.get_item_count(preferred)
    if n_avail > 5 then
      purge = true
    end
  end

  -- remove unwanted fuel
  local contents = inv.get_contents()
  for fuel, count in pairs(contents) do
    -- if blocked or we are purging and the fuel isn't preferred
    if cfg[fuel] == true or (purge and fuel ~= preferred) then
      local n_taken = inv.remove({name=fuel, count=count})
      if n_taken > 0 then
        GlobalState.increment_item_count(fuel, n_taken)
        if n_taken == count then
          contents[fuel] = nil
        else
          contents[fuel] = count - n_taken
        end
      end
    end
  end

  -- We might have just removed all fuel
  if next(contents) == nil then
    return service_refuel_empty(entity, inv)
  end

  -- try to top off existing fuel(s)
  local added_fuel = false
  for fuel, _ in pairs(contents) do
    local fuel_prot = game.item_prototypes[fuel]
    if fuel_prot ~= nil then
      local n_need = inv.get_insertable_count(fuel) - 12
      -- start requesting when fuel is below 1/2 stack
      if n_need > fuel_prot.stack_size / 2 then
        if inv_utils.transfer_item_to_inv(entity, inv, fuel, n_need) > 0 then
          added_fuel = true
        end
      end
    end
  end
  return added_fuel
end

--[[
Remove any burnt results (no limits).
Find the best fuel for the entity and add some fuel.
returns whether fuel was added.
]]
function M.refuel_entity(entity)
  -- remove burnt results with no limits
  local br_inv = entity.get_burnt_result_inventory()
  if br_inv ~= nil and not br_inv.is_empty() then
    GlobalState.items_inv_to_net(br_inv)
  end

  -- add fuel
  local f_inv = entity.get_fuel_inventory()
  if f_inv ~= nil then
    return M.service_refuel(entity, f_inv)
  end
  return false
end


--[[
Service a recipe, adding stuff to the inventory.
Note that get_insertable_count() doesn't work on assembling maching ingredients, as it
will assume 1 stack.

@info is the entity info
@entity is info.entity
@inv is the input inventory
@recipe is the recipe, uses the following fields (if you want to fake it)
  - energy = number
  - ingredients = { { type: string, name: string, amount: number } }

returns whether we failed to get enough for one recipe
]]
function M.service_recipe_inv(info, entity, inv, recipe)
  local is_short = false
  if recipe ~= nil and inv ~= nil then
    -- calculate the recipe multiplier
    local rtime = recipe.energy / entity.crafting_speed -- time to finish one recipe
    local svc_ticks = info.service_tick_delta or (60 * 60) -- assume 60 seconds on first service
    local mult = math.ceil(svc_ticks / (rtime * 60))

    local contents = inv.get_contents()
    for _, ing in ipairs(recipe.ingredients) do
      if ing.type == "item" then
        -- need enough for at least 1 recipe
        local n_rmult = math.floor(math.max(ing.amount, ing.amount * mult))
        local n_avail = GlobalState.get_item_count(ing.name)
        local n_have = (contents[ing.name] or 0)
        local n_want = n_rmult - n_have
        local n_trans = math.min(n_avail, n_want)
        if n_trans > 0 then
          local n_added = inv.insert{ name=ing.name, count=n_trans }
          if n_added > 0 then
            GlobalState.increment_item_count(ing.name, -n_added)
          end
        elseif n_want > 0 and n_have < ing.amount then
          -- only report shortage for one recipe instance
          GlobalState.missing_item_set(ing.name, entity.unit_number, ing.amount - n_have)
          is_short = true
        end
      end
    end
  end
  return is_short
end

function M.service_reload_ammo_type(entity, inv, ammo_categories)
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
        inv_utils.transfer_item_to_inv_max(entity, inv, best_ammo)
        -- it is remotely possible that there can be multiple ammo_categories...
        --return
      end
    end
  else
    -- top off existing ammo
    for name, _ in pairs(inv.get_contents()) do
      inv_utils.transfer_item_to_inv_max(entity, inv, name)
    end
  end
end

function M.service_reload_ammo_car(entity, inv)
  if inv == nil then
    clog("%s: weird. no ammo inv", entity.name)
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
      inv_utils.transfer_item_to_inv_max(entity, inv, stack.name)
    else
      -- empty: find good ammo to add
      local ammo_name = GlobalState.get_best_available_ammo(inv_cat[idx])
      if ammo_name ~= nil then
        inv_utils.transfer_item_to_inv_max(entity, inv, ammo_name)
      end
    end
  end
end


function M.update_network_chest_provider(info)
  local inv = info.entity.get_output_inventory()
  local contents = inv.get_contents()
  local n_empty = inv.count_empty_stacks(false, false)

  inv.clear()

  -- move everything we can to the network
  for item, count in pairs(contents) do
    if count > 0 then
      GlobalState.increment_item_count(item, count)
    end
  end

  if n_empty == 0 then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_INC * 5
  elseif n_empty < 2 then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
  elseif n_empty > 4 then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC
  else
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
  end
end

return M
