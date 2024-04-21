--[[
Services entities of type 'lab'.
]]
local GlobalState = require "src.GlobalState"
local inv_utils = require("src.inv_utils")
local ServiceEntity = require("src.ServiceEntity")
local Event = require('__stdlib__/stdlib/event/event')

local M = {}

-- list of recipes that creates the science pack
M.item_recipes = {}
-- key=force.name, val={ [item_name]=boolean }
M.force_item_avail = {}

--[[
Get the list of recipes that create the specified item.
This will not change during a run and does not need to be saved.
]]
function M.recipes_for_item(item_name)
  local rs = M.item_recipes[item_name]
  if rs == nil then
    rs = game.get_filtered_recipe_prototypes({
      { filter="has-product-item", elem_filters = {{ filter = "name", name = item_name }} }
    })
    -- convert to a table of [recipe.name]=true, as we don't want the recipe here
    local rnt = {}
    for k, _ in pairs(rs) do
      rnt[k] = true
    end
    M.item_recipes[item_name] = rnt
  end
  return rs
end

function M.force_item_available(force, item_name)
  local spb = M.force_item_avail[force.name]
  if spb == nil then
    spb = {}
    M.force_item_avail[force.name] = spb
  end
  -- see if the result is cached
  local res = spb[item_name]
  if type(res) == "boolean" then
    return res
  end

  -- get all recipes for the item
  local is_avail = false
  for rn, _ in pairs(M.recipes_for_item(item_name)) do
    local rr = force.recipes[rn]
    if rr ~= nil and rr.enabled then
      is_avail = true
      -- print(string.format("service_lab: %s available due to recipe %s", item_name, rn))
    end
  end
  spb[item_name] = is_avail
  return is_avail
end

function M.lab_service(info)
  local entity = info.entity
  local status = entity.status
  local pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC

  -- handle refueling (burner lab)
  ServiceEntity.refuel_entity(entity)

  -- get the lab_input inventory
  local inv = entity.get_inventory(defines.inventory.lab_input)
  if inv == nil then
    return
  end

  -- TODO: calculate the rate of research to see how many science packs are needed
  local sp_count = 10

  for _, item in ipairs(entity.prototype.lab_inputs) do
    if M.force_item_available(entity.force, item) then
      inv_utils.transfer_item_to_inv_level(entity, inv, item, sp_count)
    end
  end

  -- inc pri if the lab had stopped due to a missing science pack
  if status ~= entity.status then
    pri = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
  end

  return pri
end

local function print_entity_status()
  for k, v in pairs(defines.entity_status) do
    print(string.format("%s => %s", k, v))
  end
end

--[[
Some research was just completed.
While we could see which items are afected by looking at the products, it is
easier to just reset anything that was determined to NOT be available previously.
]]
local function on_research_finished(event)
  print_entity_status()
  local force = event.research.force
  if force ~= nil then
    local spb = M.force_item_avail[force.name]
    if spb ~= nil then
      for item_name, val in pairs(spb) do
        if val == false then
          spb[item_name] = nil
          --print(string.format("%s: cleared item %s", force.name, item_name))
        end
      end
    end
  end
end

--[[
Research was un-done.
Dump the whole cache for the force.
Not tested.
]]
local function on_research_reversed(event)
  local force = event.research.force
  if force ~= nil then
    local spb = M.force_item_avail[force.name]
    if spb ~= nil then
      M.force_item_avail[force.name] = {}
    end
  end
end

Event.on_event(defines.events.on_research_finished, on_research_finished)
Event.on_event(defines.events.on_research_reversed, on_research_reversed)

GlobalState.register_service_task("lab", {
  service=M.lab_service
})

return M
