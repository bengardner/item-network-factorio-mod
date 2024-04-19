--[[
Services the "assembling-machine" type.
]]
local GlobalState = require "src.GlobalState"
local string = require('__stdlib__/stdlib/utils/string')
local ServiceEntity = require("src.ServiceEntity")
--local clog = require("src.log_console").log

local M = {}

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

--REVISIT: config option for testing
local flush_whole_system = false

--[[
The recipe just changed. Handle it.
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
  ServiceEntity.refuel_entity(entity)

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
    ServiceEntity.service_recipe_inv(info, entity, inp_inv, recipe)
  end
  return pri
end

local function assembling_machine_paste(dst_info, source)
  GlobalState.assembler_check_recipe(dst_info.entity)
end

local function assembling_machine_clone(dst_info, src_info)
  assembling_machine_paste(dst_info, src_info.entity)
end

GlobalState.register_service_task("assembling-machine", {
  paste=assembling_machine_paste,
  clone=assembling_machine_clone,
  service=M.service_assembling_machine
})

return M
