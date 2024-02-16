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

-- hacky replacement for existing fuel
local promote_fuel = {
  wood = 'coal',
  coal = 'processed-fuel',
}


local function service_refuel_empty(entity, inv)
  local fuel_name, n_avail = GlobalState.get_best_available_fuel(entity)
  if fuel_name == nil or n_avail == nil then
    return
  end
  --sclog("best fuel for %s is %s and we have %s", entity.name, fuel_name, n_avail)
  if n_avail > 0 then
    local prot = game.item_prototypes[fuel_name]
    local n_add = (#inv * prot.stack_size) -- - 12
    transfer_item_to_inv(entity, inv, fuel_name, math.min(n_avail, n_add))
  end
  return
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
]]
local function service_refuel(entity, inv)
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
    service_refuel_empty(entity, inv)
    return
  end

  -- try to top off existing fuel(s)
  for fuel, count in pairs(contents) do
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

function M.refuel_entity(entity)
  -- add fuel
  local f_inv = entity.get_fuel_inventory()
  if f_inv ~= nil then
    service_refuel(entity, f_inv)
  end
  -- remove burnt results with no limits
  local br_inv = entity.get_burnt_result_inventory()
  if br_inv ~= nil and not br_inv.is_empty() then
    GlobalState.items_inv_to_net(br_inv)
  end
end

local function transfer_fluid_to_entity(entity, name, n_want)
  if n_want > 0 then
    local n_avail, temp = GlobalState.get_fluid_count(name, nil)
    if n_avail > 0 then
      local n_trans = math.min(n_want, n_avail)
      local n_added = entity.insert_fluid( { name=name, amount=n_trans })
      if n_added > 0 then
        print(string.format("fluid: want=%s avail=%s added=%s", n_want, n_avail, n_added))
        GlobalState.set_fluid_count(name, temp, n_avail - n_added)
      end
    end
  end
end
----

--[[
Service a recipe, adding stuff to the inventory.
Note that get_insertable_count() doesn't work on assembling maching ingredients, as it
will assume 1 stack.

@info is the entity info
@entity is info.entity
@inv is the input inventory
@recipe is the recipe
]]
local function service_recipe_inv(info, entity, inv, recipe)
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
    for name, _ in pairs(inv.get_contents()) do
      transfer_item_to_inv_max(entity, inv, name)
    end
  end
end

local function service_reload_ammo_car(entity, inv)
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

  if entity.type == "car" then
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

--[[
  Search all connected entities, looking for "network-tank-requester"

  @visited is a table of all unit_numbers that we have visited key=unit_number,val=entity|false
]]
local function search_for_ntr(fluid_name, fluidbox, sysid, visited)
  print(string.format("search_for_ntr %s %s %s", fluid_name, sysid, serpent.line(visited)))
  -- iterate over fluidboxes
  for idx = 1, #fluidbox do
    -- only care about same system ids
    local sid = fluidbox.get_fluid_system_id(idx)
    if sid == sysid then
      local fca = fluidbox.get_connections(idx)
      for _, fc in ipairs(fca) do
        local oo = fc.owner
        local oun = oo.unit_number
        if visited[oun] == nil then
          visited[oun] = true
          if oo.name == "network-tank-requester" then
            local info = GlobalState.entity_info_get(oun)
            if info ~= nil and info.config ~= nil then
              if info.config.type == "take" and info.config.fluid ~= fluid_name then
                print(string.format(" NEED TO RESET %s", serpent.line(info)))
                info.config.type = "auto"
                GlobalState.queue_reservice(info)
              end
            end
          else
            search_for_ntr(fluid_name, fc, sysid, visited)
          end
        end
      end
    end
  end
end

local flush_whole_system = false

--[[
  The recipe just changed.
]]
local function handle_recipe_changed(info, entity, old_recipe, new_recipe)
  --print(string.format("[%s] %s: RECIPE CHANGED %s => %s", info.unit_number, entity.name, old_recipe, new_recipe))

  local fluidbox = entity.fluidbox

  if flush_whole_system then
    -- find any connected "network-tank-requester" and check the fluid vs expected fluid. set config to auto if wrong.
    for idx = 1, #fluidbox do
      local visited = {}
      -- don't visit here again
      visited[entity.unit_number] = true
      local fluid_name = fluidbox.get_locked_fluid(idx)
      if fluid_name ~= nil then
        local sysid = fluidbox.get_fluid_system_id(idx)
        if sysid ~= nil then
          local prot = fluidbox.get_prototype(idx)
          if prot.object_name ~= 'LuaFluidBoxPrototype' then
            prot = prot[1]
          end
          if prot.production_type == "input" then
            search_for_ntr(fluid_name, fluidbox, sysid, visited)
            local cont = fluidbox.get_fluid_system_contents(idx)
            for k, c in pairs(cont) do
              if k ~= fluid_name then
                -- REVISIT: no temperature, so we just dump it
                fluidbox.flush(idx, k)
              end
            end
          end
        end
      end
    end
  else
    -- set any directly-connected "network-tank-requester" to "auto" if the fluid doesn't match
    for idx = 1, #fluidbox do
      -- check locked_fluids
      local locked_fluid = fluidbox.get_locked_fluid(idx)
      if locked_fluid ~= nil then
        local prot = fluidbox.get_prototype(idx)
        if prot.object_name ~= 'LuaFluidBoxPrototype' then
          prot = prot[1]
        end
        if prot.production_type == "input" then
          local fca = fluidbox.get_connections(idx)
          for _, fc in ipairs(fca) do
            if fc.owner.name == "network-tank-requester" then
              local info = GlobalState.entity_info_get(fc.owner.unit_number)
              if info ~= nil and info.config ~= nil then
                if info.config.type == "take" and info.config.fluid ~= locked_fluid then
                  info.config.type = "auto"
                  GlobalState.queue_reservice(info)
                end
              end
            end
          end
        end
      end
    end
  end
end

--[[
  Service an entity of type 'assembling-machine'.
   - refuel
   - remove output
   - add ingredients

Ingredient amounts will follow the service period and time to finish production.

Priority will adjust based on whether the output is full.
  output empty => longest period
  output full, no room in net => shut down (remove inputs)
  output full, all move to net => increase priority
  output not full => decrease priority
]]
function M.service_assembling_machine(info)
  local entity = info.entity
  local pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME

  -- handle refueling
  M.refuel_entity(entity)

  --clog("Service [%s] %s status=%s", entity.unit_number, entity.name, entity.status)

  local out_inv = entity.get_output_inventory()
  local inp_inv = entity.get_inventory(defines.inventory.assembling_machine_input)

  local old_status = entity.status
  local was_empty = out_inv.is_empty()

  if not was_empty then
    -- move output items to net
    GlobalState.items_inv_to_net_with_limits(out_inv)
  end

  if old_status == defines.entity_status.full_output then
    if not out_inv.is_empty() then
      -- was full and still can't send off items, so shut off, return inputs
      GlobalState.items_inv_to_net(inp_inv)
      return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
    end
    -- output is now empty, was full. service more often
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
  elseif was_empty then
    -- max service period: output was empty, so jump to the max
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  else
    -- service less often: wasn't empty or full
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC
  end

  -- check for a recipe change
  local recipe = entity.get_recipe()
  if recipe ~= nil then
    local recipe_name = recipe.name
    if info.recipe_name ~= recipe_name then
      handle_recipe_changed(info, entity, info.recipe_name, recipe_name)
      info.recipe_name = recipe_name
    end

    -- ingredients automatically adjusts to service period
    service_recipe_inv(info, entity, inp_inv, recipe)
  end
  return pri
end

local function assembling_machine_paste(dst_info, source)
  print(string.format("[%s] paste", dst_info.unit_number, source.unit_number))
  GlobalState.assembler_check_recipe(dst_info.entity)
end

local function assembling_machine_clone(dst_info, src_info)
  assembling_machine_paste(dst_info, src_info.entity)
end

local ore_to_furnce_recipe

--[[
Determine the recipe name based on ore based on the inputs, last_recipe or info.ore_name
]]
function M.furnace_get_ore_recipe(ore_name)
  local recipe_name = GlobalState.furnace_get_ore_recipe(ore_name)
  -- go with whatever was last configured (inputs and outputs are empty)
  return info.ore_name
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

--[[
  Get the required refill level.
]]
function M.furnace_get_ore_count(info)
  if info.ore_name == nil then
    return nil
  end
  local recipe = GlobalState.furnace_get_ore_recipe(info.ore_name)
  if recipe == nil then
    return nil
  end

  local rtime = recipe.energy / info.entity.crafting_speed -- time to finish one recipe
  local svc_ticks = info.service_tick_delta or (10 * 60) -- assume 60 seconds on first service
  local mult = math.ceil(svc_ticks / (rtime * 60))

  local ing = recipe.ingredients[1]
  --print(string.format("Furnace: name=%s amount=%s mult=%s", ing.name, ing.amount, mult))
  return ing.amount * mult
end

--[[
This services a furnace.
 - adds fuel
 - removes burnt results
 - removes output
 - adds ore

NOTE that we can't get the current recipe.
Determining the ore to add:
 - same ore(s) as is currently present in the input
   - record in info.ore_name
 - use info.ore_name
 - check the output
]]
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
    local ore_count = M.furnace_get_ore_count(info)
    if ore_count ~= nil then
      --print(string.format("ore level: %s %s", info.ore_name, ore_count))
      transfer_item_to_inv_level(entity, inv_src, info.ore_name, ore_count)
    else
      --print(string.format("ore max: %s", info.ore_name))
      transfer_item_to_inv_max(entity, inv_src, info.ore_name)
    end
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

  -- try to load each lib_input at a minimum level
  -- clog("lab inputs: %s", serpent.line(entity.prototype.lab_inputs))
  for _, item in ipairs(entity.prototype.lab_inputs) do
    -- want to check force.technologies, but that is not accurate
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

GlobalState.register_service_task("assembling-machine", {
  create=M.create,
  paste=assembling_machine_paste,
  clone=assembling_machine_clone,
  service=M.service_assembling_machine
})

return M
