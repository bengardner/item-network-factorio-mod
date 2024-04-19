local GlobalState = require "src.GlobalState"
local Event = require('__stdlib__/stdlib/event/event')
local constants = require('src.constants')

local function production_supply_force(force)
  -- item cheat is simple
  for item_name, item_count in pairs(force.item_production_statistics.input_counts) do
    if item_count > 0 then
      local n_ins = math.min(item_count, GlobalState.get_insert_count(item_name))
      if n_ins > 0 then
        GlobalState.increment_item_count(item_name, n_ins)
      end
    end
  end

  -- fluid cheat has to do each temperature
  local limits = GlobalState.get_limits()
  local fluids = GlobalState.get_fluids()
  for fluid_name, fluid_count in pairs(force.fluid_production_statistics.input_counts) do
    for temps, amount in pairs(fluids[fluid_name] or {}) do
      local limit_key = string.format("%s@%s", fluid_name, temps)
      local flim = limits[limit_key] or constants.UNLIMITED
      local n_ins = math.max(0, math.min(flim - amount, fluid_count))
      if n_ins > 0 then
        GlobalState.increment_fluid_count(fluid_name, temps, n_ins)
      end
    end
  end
end

local function production_supply_check()
  local sv = settings.global["item-network-cheat-production-duplicate"].value
  if type(sv) == "number" and sv > 0 then
    local now = game.tick
    local ps = global.production_supply
    if type(ps) ~= "table" then
      ps = {}
      global.production_supply = ps
    end
    for _, force in pairs(game.forces) do
      local ft = ps[force.name] or 0
      if now >= ft then
        ps[force.name] = now + (sv * 60)
        production_supply_force(force)
      end
    end
    global.production_supply = ps
  end
end

Event.on_nth_tick(60, production_supply_check)
