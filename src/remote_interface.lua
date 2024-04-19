--[[
  Registers the remote interface.
]]
local GlobalState = require "src.GlobalState"

--[[
Put items in the network inventory.
No limit checks are performed.
]]
local function deposit_items(force, items)
  -- check force
  local ff = game.forces[force]
  if ff == nil then
    return string.format('deposit_items: invalid force: %s', force)
  end

  local function do_item(name, count)
    if type(name) == "string" and type(count) == "number" and count > 0 then
      if game.item_prototypes[name] ~= nil then
        print(string.format("deposit_items: %s %s %s", ff.name, name, count))
        GlobalState.increment_item_count(name, count)
        --GlobalState.items_increment_count(ff.name, name, count)
      end
    end
  end

  print(string.format("deposit_items: %s %s", ff.name, serpent.line(items)))
  if type(items) == "table" then
    if items.name ~= nil and items.count ~= nil then
      do_item(items.name, items.count)
    else
      for _, kv in ipairs(items) do
        do_item(kv.name, kv.count)
      end
    end
  end
  return true
end

--[[
Remove items from the network inventory.
returns the items that were taken.
]]
local function withdraw_items(force, items)
  local result = {}

  -- check force
  local ff = game.forces[force]
  if ff == nil then
    return string.format('deposit_items: invalid force: %s', force)
  end

  local function do_item(name, count)
    if type(name) == "string" and type(count) == "number" and count > 0 then
      if game.item_prototypes[name] ~= nil then
        local nhave = GlobalState.get_item_count(name)
        --local nhave = GlobalState.items_get_count(ff.name, name)
        local ntake = math.min(nhave, count)
        if ntake > 0 then
          GlobalState.increment_item_count(name, -ntake)
          --GlobalState.items_increment_count(ff.name, name, -ntake)
          print(string.format("withdraw_items: %s %s %s", ff.name, name, ntake))
          result[name] = ntake
        end
      end
    end
  end

  print(string.format("withdraw_items: %s %s", ff, serpent.line(items)))

  if type(items) == "table" then
    if items.name ~= nil and items.count ~= nil then
      do_item(items.name, items.count)
    else
      for _, kv in ipairs(items) do
        do_item(kv.name, kv.count)
      end
    end
  end

  return result
end

--[[
Put a fluid into the network inventory
@fluid { name -> string, amount -> number, temperature -> number? }
Uses the default temperature is not specified.
]]
local function deposit_fluid(force, fluid)
  print(string.format("deposit_fluid: %s", serpent.line(fluid)))
end

--[[
Take a fluid from the network inventory.
@fluid_req is { name -> string, amount -> number, temperature -> number?, minimum_temperature -> number?, maximum_temperature? }
returns a 'Fluid' { name=fluid_name, amount=fluid_amount, temperature=temp }
]]
local function withdraw_fluid(force, fluid_req)
  print(string.format("withdraw_fluid: %s", serpent.line(fluid_req)))
end

--[[
Grab the item table.
format: { [item_name] = item_count }
]]
local function items_get_content(force)
end

--[[
Grab the fluid table.
format: { [fluid_name] = { [temperaturex1000] = amount } }
]]
local function fluids_get_content(force)
end

remote.add_interface("item-network",
  {
    deposit_items = deposit_items,
    withdraw_items = withdraw_items,
    deposit_fluid = deposit_fluid,
    withdraw_fluid = withdraw_fluid,
    -- query functions
    items_get_content = items_get_content,
    fluids_get_content = fluids_get_content,
  })
