--[[
  Used to get a default limit for an item.
  Right now. this is mostly based on the subgroup,

  Probably should re-do this as a table of item-name => count.
]]
local M = {}

-- this belonds in a utility file
local function str_endswith(text, tag)
  if type(text) == "string" and type(tag) == "string" then
    return #tag <= #text and string.sub(text, 1 + #text - #tag) == tag
  end
  return false
end

-- this should be read from a config file
local default_limits = {
  ["crude-oil"] = 5000000,
  ["heavy-oil"] = 5000000,
  ["light-oil"] = 5000000,
  ["lubricant"] = 50000,
  ["petroleum-gas"] = 5000000,
  ["steam"] = 5000000,
  ["sulfuric-acid"] = 50000,
  ["water"] = 5000000,
  ["accumulator"] = 100,
  ["advanced-circuit"] = 200,
  ["arithmetic-combinator"] = 50,
  ["artillery-turret"] = 50,
  ["assembling-machine-1"] = 100,
  ["assembling-machine-2"] = 100,
  ["assembling-machine-3"] = 100,
  ["battery"] = 500,
  ["battery-equipment"] = 20,
  ["battery-mk2-equipment"] = 20,
  ["beacon"] = 20,
  ["belt-immunity-equipment"] = 5,
  ["big-electric-pole"] = 100,
  ["boiler"] = 20,
  ["burner-generator"] = 20,
  ["burner-inserter"] = 20,
  ["burner-mining-drill"] = 20,
  ["centrifuge"] = 20,
  ["chemical-plant"] = 20,
  ["coal"] = 500000000,
  ["coin"] = 500000000,
  ["concrete"] = 500,
  ["constant-combinator"] = 50,
  ["construction-robot"] = 100,
  ["copper-cable"] = 5000,
  ["copper-ore"] = 500000000,
  ["copper-plate"] = 50000,
  ["crude-oil-barrel"] = 50,
  ["decider-combinator"] = 50,
  ["discharge-defense-equipment"] = 5,
  ["electric-energy-interface"] = 50,
  ["electric-engine-unit"] = 100,
  ["electric-furnace"] = 100,
  ["electric-mining-drill"] = 100,
  ["electronic-circuit"] = 800,
  ["empty-barrel"] = 100,
  ["energy-shield-equipment"] = 5,
  ["energy-shield-mk2-equipment"] = 5,
  ["engine-unit"] = 100,
  ["exoskeleton-equipment"] = 10,
  ["explosives"] = 50000,
  ["express-loader"] = 50,
  ["express-splitter"] = 50,
  ["express-transport-belt"] = 200,
  ["express-underground-belt"] = 50,
  ["fast-inserter"] = 50,
  ["fast-loader"] = 50,
  ["fast-splitter"] = 50,
  ["fast-transport-belt"] = 200,
  ["fast-underground-belt"] = 50,
  ["filter-inserter"] = 50,
  ["flamethrower-turret"] = 50,
  ["flying-robot-frame"] = 100,
  ["fusion-reactor-equipment"] = 10,
  ["gate"] = 100,
  ["green-wire"] = 100,
  ["gun-turret"] = 100,
  ["hazard-concrete"] = 500,
  ["heat-exchanger"] = 50,
  ["heat-interface"] = 50,
  ["heat-pipe"] = 100,
  ["heavy-oil-barrel"] = 50,
  ["infinity-chest"] = 50,
  ["infinity-pipe"] = 50,
  ["inserter"] = 50,
  ["iron-chest"] = 50,
  ["iron-gear-wheel"] = 5000,
  ["iron-ore"] = 5000000000,
  ["iron-plate"] = 10000,
  ["iron-stick"] = 10000,
  ["lab"] = 10,
  ["land-mine"] = 100,
  ["landfill"] = 500,
  ["laser-turret"] = 50,
  ["light-oil-barrel"] = 50,
  ["linked-belt"] = 50,
  ["linked-chest"] = 50,
  ["loader"] = 50,
  ["logistic-chest-active-provider"] = 50,
  ["logistic-chest-buffer"] = 50,
  ["logistic-chest-passive-provider"] = 50,
  ["logistic-chest-requester"] = 50,
  ["logistic-chest-storage"] = 50,
  ["logistic-robot"] = 100,
  ["long-handed-inserter"] = 50,
  ["low-density-structure"] = 100,
  ["lubricant-barrel"] = 50,
  ["medium-electric-pole"] = 100,
  ["night-vision-equipment"] = 5,
  ["nuclear-fuel"] = 100,
  ["nuclear-reactor"] = 8,
  ["offshore-pump"] = 10,
  ["oil-refinery"] = 50,
  ["personal-laser-defense-equipment"] = 10,
  ["personal-roboport-equipment"] = 10,
  ["personal-roboport-mk2-equipment"] = 10,
  ["petroleum-gas-barrel"] = 50,
  ["pipe"] = 400,
  ["pipe-to-ground"] = 100,
  ["plastic-bar"] = 50000,
  ["player-port"] = 50,
  ["power-switch"] = 50,
  ["processing-unit"] = 50,
  ["programmable-speaker"] = 50,
  ["pump"] = 50,
  ["pumpjack"] = 10,
  ["radar"] = 50,
  ["rail-chain-signal"] = 50,
  ["rail-signal"] = 50,
  ["red-wire"] = 100,
  ["refined-concrete"] = 500,
  ["refined-hazard-concrete"] = 500,
  ["roboport"] = 10,
  ["rocket-control-unit"] = 50,
  ["rocket-fuel"] = 5000,
  ["rocket-part"] = 5000,
  ["rocket-silo"] = 1,
  ["satellite"] = 50,
  ["simple-entity-with-force"] = 50,
  ["simple-entity-with-owner"] = 50,
  ["small-electric-pole"] = 100,
  ["small-lamp"] = 50,
  ["solar-panel"] = 100,
  ["solar-panel-equipment"] = 50,
  ["solid-fuel"] = 5000,
  ["splitter"] = 50,
  ["stack-filter-inserter"] = 50,
  ["stack-inserter"] = 50,
  ["steam-engine"] = 50,
  ["steam-turbine"] = 50,
  ["steel-chest"] = 50,
  ["steel-furnace"] = 200,
  ["steel-plate"] = 5000,
  ["stone"] = 5000000000,
  ["stone-brick"] = 500,
  ["stone-furnace"] = 100,
  ["stone-wall"] = 500,
  ["storage-tank"] = 50,
  ["substation"] = 100,
  ["sulfur"] = 5000000,
  ["sulfuric-acid-barrel"] = 50,
  ["train-stop"] = 10,
  ["transport-belt"] = 100,
  ["underground-belt"] = 50,
  ["uranium-235"] = 5000000,
  ["uranium-238"] = 5000000,
  ["uranium-fuel-cell"] = 5000000,
  ["uranium-ore"] = 5000000,
  ["used-up-uranium-fuel-cell"] = 5000000,
  ["water-barrel"] = 500,
  ["wood"] = 5000000,
  ["wooden-chest"] = 50,
}

-- return a hopefully sane default to help new players
function M.get_default_limit(item)
  -- see if we have if by name
  local deflim = default_limits[item]
  if deflim ~= nil then
    return deflim
  end

  -- try by group/subgroup
  local prot = game.item_prototypes[item]
  if prot == nil then
    -- not an item; probably a fluid. Go with 500 K.
    return 500000
  end

  if str_endswith(prot.name, "-remote") then
    -- coverts spidertron remote and a few others
    return 1
  elseif prot.subgroup.name == "raw-resource" or prot.name == "uranium-238" then
    -- example: iron-ore
    return 1000000 -- 1 M
  elseif prot.subgroup.name == "raw-material" then
    -- example: iron-plate
    return 50000 -- 50 K
  elseif prot.subgroup.name == "ammo" then
    return 10 * prot.stack_size
  elseif prot.subgroup.name == "armor" then
    return 1
  elseif prot.subgroup.name == "transport" then
    return 1
  elseif prot.subgroup.name == "defensive-structure" then
    return 1
  elseif prot.subgroup.name == "capsule" then
    return 50
  elseif prot.subgroup.name == "energy" then
    return 50
  elseif prot.subgroup.name == "circuit-network" then
    return 50
  elseif prot.subgroup.name == "gun" then
    return 5
  elseif prot.group.name == "intermediate-products" or prot.subgroup.name == "intermediate-product" then
    return 10 * prot.stack_size
  elseif prot.subgroup.name == "production-machine" then
    return 50
  elseif prot.subgroup.name == "belt" then
    return 200
  elseif prot.subgroup.name == "inserter" then
    return 200
  elseif prot.subgroup.name == "train-transport" then
    if prot.name == "rail" then
      -- need lots of track
      return 8 * prot.stack_size
    else
      -- locomotives, train cars, signals, etc
      return prot.stack_size
    end
  elseif prot.group.name == "logistics" then
    if prot.subgroup.name == "terrain" then
      -- concrete, cliff explosive, etc
      return 5 * prot.stack_size
    end
    -- all sorts of stuff. bets & inserters handled above
    return prot.stack_size
  elseif prot.group.name == "module" then
    if prot.name == "beacon" then
      return prot.stack_size
    end
    return 2 * prot.stack_size
  else
    -- game.print(string.format("default limit: fell off the bottom name=[%s] group=[%s] subgroup=[%s]",
    --   prot.name, prot.group.name, prot.subgroup.name))
    return 2 * prot.stack_size
  end
end

return M
