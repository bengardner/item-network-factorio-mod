--[[
Services furnaces.
 - refuel
 - remove output items
 - add input items

A furnace may have 1 or 0 item input slots.
It may also have fluid inputs, but that doesn't matter here.
Track the item name for the input in info.config.ore_name.
Also save the recipe name in info.config.recipe_name.

The 'ore_name' detection logic is as follows:
 - if there are no input slots, then ore_name is nil. Done.
 - if there is something in the input inventory, we use that.
 - if the input inventory is empty, use info.config.ore_name.
 - if info.config.ore_name is nil, then check entity.previous_recipe for inputs

If a furnace is fluid-only, then we only remove outputs, assuming there are item slots.
]]
local GlobalState = require "src.GlobalState"
--local clog = require("src.log_console").log
local inv_utils = require("src.inv_utils")
local ServiceEntity = require("src.ServiceEntity")

local M = {}

-- local recipe cache, as the mapping can't change during a run
-- and we don't need to save or sync this info.
global.recipes_input = {} -- { key=furnace_name, val={ key=ore_name, val=recipe } }
global.recipes_output = {} -- { key=furnace_name, val={ key=item_name, val=recipe } }

local function item_from_recipe(recipe_name)
  if recipe_name ~= nil then
    local recipe = game.recipe_prototypes[recipe_name]
    if recipe ~= nil then
      for _, ing in ipairs(recipe.ingredients) do
        if ing.type == "item" then
          return ing.name
        end
      end
    end
  end
  return nil
end

--[[
Sets info.config.ore_name and info.config.recipe_name.
]]
function M.set_ore_name(info, ore_name)
  local cfg = info.config
  if cfg == nil then
    cfg = {}
    info.config = cfg
  end
  cfg.ore_name = ore_name
  local recipe_name = nil
  if ore_name ~= nil then
    local rp = M.furnace_get_recipe(info.entity, ore_name)
    if rp ~= nil then
      recipe_name = rp.name
      print(string.format("%s[%s] set ore %s recipe %s", info.entity.name, info.unit_number,
        ore_name, recipe_name))
    end
  end
  cfg.recipe_name = recipe_name
end

--[[
Gets info.config.ore_name
]]
function M.get_ore_name(info)
  return (info.config or {}).ore_name
end

--[[
Gets info.config.recipe_name
]]
function M.get_recipe_name(info)
  return (info.config or {}).recipe_name
end

function M.set_recipe_name(info, recipe_name)
  -- TODO: verify that the recipe is valid
  if info.config.recipe_name ~= recipe_name then
    info.config.new_recipe_name = recipe_name
    GlobalState.queue_reservice(info)
    print(string.format("%s[%s] set recipe %s (was %s)",
          info.entity.name, info.unit_number,
          recipe_name, info.config.recipe_name))
  end
--[[
  if recipe_name then
    local recipe = game.recipe_prototypes[recipe_name]
    if recipe then
      for _, ing in ipairs(recipe.ingredients) do
        if ing.type == "item" then
          info.config.ore_name = ing.name
          print(string.format("%s[%s] set recipe %s item %s", info.entity.name, info.unit_number,
            recipe_name, ing.name))
        end
      end
    end
  end
]]
end

--[[
Scan the crafting_categories and find the first matching recipe.
  @entity used for entity.name and entity.prototype.crafting_categories
  @item_name the item to match
  @cache_table  M.recipe_input or M.recipe_output
  @filter_name "has-ingredient-item" or "has-product-item"
]]
local function get_recipe(entity, item_name, cache_table, filter_name)
  local eor = cache_table[entity.name]
  if eor == nil then
    eor = {}
    cache_table[entity.name] = eor
  end

  local rr = eor[item_name]
  if rr ~= nil then
    return rr
  end

  -- iterate over the crafting_categories
  for cc, _ in pairs(entity.prototype.crafting_categories) do
    -- find furnace recipes that have the one input item and a matching category
    local rps = game.get_filtered_recipe_prototypes{
      { filter="category", category=cc },
      { mode="and", filter="hidden", invert=true },
      { mode="and", filter=filter_name, elem_filters={
          { filter="name", name=item_name }
        },
      },
    }
    -- grab the first match (there should only be one!)
    -- NOTE that we do not take any fluids into account here!
    for _, r in pairs(rps) do
      eor[item_name] = r
      return r
    end
  end

  return nil
end

--[[
Determine the recipe based on the entity and the ore_name.
returns the recipe prototype.
]]
function M.furnace_get_recipe(entity, ore_name)
  return get_recipe(entity, ore_name, global.recipes_input, "has-ingredient-item")
end

--[[
Guess the recipe based on the output inventory content.
returns the recipe prototype.
]]
function M.furnace_get_recipe_output(entity, item_name)
  return get_recipe(entity, item_name, global.recipes_output, "has-product-item")
end

--[[
Paste the configuration.
We can only go off of the source inventory and info.config.ore_name.
]]
local function furnace_paste(dst_info, source)
  -- we only handle same-type pasting (furnace to furnace).
  local dest = dst_info.entity
  if dest.type ~= source.type then
    return
  end

  -- We have to know about the source
  local src_info = GlobalState.entity_info_get(source.unit_number)
  if src_info == nil then
    -- clog("paste: no source info")
    return
  end

  -- refresh the source ore_name, as the furnace may not have been serviced
  -- since adding items to the input.
  local ore_name = M.furnace_get_ore(src_info)
  if ore_name == nil or M.get_ore_name(dst_info) == ore_name then
    -- not changing dst_info.config.ore_name
    return
  end

  -- ore_name changed: update the ore_name in the dest
  M.set_ore_name(dst_info, ore_name)

  -- clog("paste: ore=%s", serpent.line(dst_info.config.ore_name))

  -- force-dump existing ingredients and output
  local dst_ing_inv = dest.get_inventory(defines.inventory.furnace_source)
  GlobalState.items_inv_to_net(dst_ing_inv)
  GlobalState.items_inv_to_net(dest.get_output_inventory())

  -- if we have a recipe, add some input items
  if dst_info.recipe_name ~= nil then
    local recipe_proto = game.recipe_prototypes[dst_info.recipe_name]
    if recipe_proto ~= nil then
      -- start with request_paste_multiplier items
      local level = recipe_proto.request_paste_multiplier
      for _, ing in ipairs(recipe_proto.ingredients) do
        if ing.type == "item" and ing.name == ore_name then
          -- adjust the request to the ingredient amount
          level = level * ing.amount
          break
        end
      end
      inv_utils.transfer_item_to_inv_level(dest, dst_ing_inv, ore_name, level)
      return
    end
  end

  -- try to top off the inputs with an unknown recipe
  inv_utils.transfer_item_to_inv_max(dest, dst_ing_inv, ore_name)

  -- NOTE: if the furnace was smelting something, the output will be
  -- purged in the service routine.
end

local function furnace_clone(dst_info, src_info)
  -- We want to fill the furnace immediately, so hook into paste without
  -- changing dst_info.config.ore_name first
  furnace_paste(dst_info, src_info.entity)
end

local function furnace_refresh_tags(info)
  -- REVISIT: do we need the nil check?
  M.set_ore_name(info, M.furnace_get_ore(info))
  return info.config
end

--[[
Determine the ore based on the inputs, previous_recipe or info.config.ore_name
 - match whatever is in the input
 - match ore_name, if set
 - check output and guess the recipe

Updates info.config.ore_name and returns info.config.ore_name.
]]
function M.furnace_get_ore(info)
  local entity = info.entity
  local src_inv = entity.get_inventory(defines.inventory.furnace_source)
  local ore_name = M.get_ore_name(info)

  -- check input inventory content
  for item, _ in pairs(src_inv.get_contents()) do
    -- set the ore_name to the first item found
    if item ~= ore_name then
      M.set_ore_name(info, item)
    end
    return item
  end

  -- empty input: go with the current ore_name, if any
  if ore_name ~= nil then
    -- no change
    return ore_name
  end

  -- this block of code will get hit if items were added to the input
  -- and fully processed between services.

  -- See if there is anything in the output and trace it back to the ore
  local out_inv = entity.get_output_inventory()
  for item, _ in pairs(out_inv.get_contents()) do
    local rprot = M.furnace_get_recipe_output(entity, item)
    if rprot ~= nil then
      --print(string.format("[%s] [%s] = p=%s i=%s", entity.unit_number, k, serpent.line(v.products), serpent.line(v.ingredients)))
      for _, ing in ipairs(rprot.ingredients) do
        if ing.type == "item" then
          M.set_ore_name(info, ing.name)
          return M.get_ore_name(info)
        end
      end
    end
  end

  return nil
end

--[[
This services a furnace.
 - adds fuel, removes burnt results
 - removes outputs
 - adds items

Adjust priority
  - using fuel too fast
    - increase priority
  - using ingrediends too fast
    - increase priority
  - filling output too fast
    - increase priority
  - else
    - decrease priority
  FUEL: status==no_fuel and we added fuel
  INPUTS: status==no_ingredients and we added inputs
  OUTPUT: status==full_output and we sent ALL to the net
]]
function M.furnace_service(info)
  local entity = info.entity
  local config = info.config
  local status = entity.status
  local pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC

  local added_fuel = ServiceEntity.refuel_entity(entity)
  if status == defines.entity_status.no_fuel and added_fuel then
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
  end

  local o_inv = entity.get_output_inventory()
  local inv_src = entity.get_inventory(defines.inventory.furnace_source)

  -- check for a new_recipe_name
  if config.new_recipe_name ~= nil then
    if config.recipe_name ~= config.new_recipe_name then
      config.recipe_name = config.new_recipe_name
      config.ore_name = item_from_recipe(config.recipe_name)
      GlobalState.items_inv_to_net(o_inv)
      GlobalState.items_inv_to_net(inv_src)
    end
    config.new_recipe_name = nil
  end

  -- grab the configured ore and the input ore
  local old_ore = M.get_ore_name(info)
  local ore_name = M.furnace_get_ore(info)

  local recipe
  local recipe_name = M.get_recipe_name(info)
  if recipe_name ~= nil then
    recipe = game.recipe_prototypes[recipe_name]
  end

  -- forcibly remove output if the ore changed
  if ore_name ~= old_ore then
    print(string.format("%s[%s] ore changed from %s to %s", entity.name, entity.unit_number,
      old_ore, ore_name))
    GlobalState.items_inv_to_net(o_inv)

  elseif not o_inv.is_empty() then
    -- force purge if and output item isn't a product of the recipe
    local force_purge = true
    if recipe ~= nil then
      for name, _ in pairs(o_inv.get_contents()) do
        -- clog("ing %s", serpent.line(recipe.ingredients))
        for _, prd in ipairs(recipe.products) do
          if prd.name == name then
            force_purge = false
            break
          end
        end
      end
    end

    if force_purge then
      GlobalState.items_inv_to_net(o_inv)
    else
      GlobalState.items_inv_to_net_with_limits(o_inv)
      -- inc pri if we were full and are now empty
      if status == defines.entity_status.full_output and o_inv.is_empty() then
        pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
      end
    end
  end

  -- add input item
  if recipe ~= nil then
    local is_short = ServiceEntity.service_recipe_inv(info, entity, inv_src, recipe)

    -- inc pri if we added stuff AND we were out of ingredients
    if status == defines.entity_status.no_ingredients and not is_short then
      pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
    end
  else
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end
  return pri
end

GlobalState.register_service_task("furnace", {
  service=M.furnace_service,
  paste=furnace_paste,
  refresh_tags=furnace_refresh_tags,
  clone=furnace_clone,
  tag="config",
})

return M
