local M = {}

function M.main()
  data:extend({
    {
      -- initial config for request chests when pasted
      -- FIXME: use the same thing as logistic requester chests
      name = "item-network-chest-size-on-paste",
      type = "int-setting",
      setting_type = "runtime-global",
      default_value = 5,
      minimum_value = 1,
      order = "000",
    },
    {
      -- adjust (upward) request amounts to satisfy the usage rate
      name = "item-network-chest-tune-request",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "001",
    },
    {
      -- adjust (upward) request amounts to satisfy the usage rate
      name = "item-network-tank-tune-request",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "002",
    },
    {
      -- satisfy player logistic requests
      name = "item-network-player-enable-logistics",
      type = "bool-setting",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "010",
    },
    {
      -- force-enables personal logistics for all players, even if not researched
      name = "item-network-player-force-logistics",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "011",
    },
    {
      -- service actitve/passive provider and requester/buffer chests
      name = "item-network-service-logistic-chest",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "020",
    },
    {
      -- drain storage logistics chests after inactivity
      name = "item-network-service-storage-chest",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "021",
    },
    {
      -- refuel anything that has a burner
      name = "item-network-service-fuel",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "030",
    },
    {
      -- add ingredients and fuel, remove output
      name = "item-network-service-furnace",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "031",
    },
    {
      -- add ingredients and fuel, remove output
      name = "item-network-service-assembler",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "032",
    },
    {
      -- add ingredients and fuel, remove output to rocket-silo
      name = "item-network-service-silo",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "032",
    },
    {
      -- add lab items
      name = "item-network-service-lab",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "033",
    },
    {
      -- add ammo to turrets and artillery
      name = "item-network-service-turret",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "033",
    },
    {
      -- scan alerts for missing materials
      name = "item-network-service-alert",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = false,
      order = "034",
    },
    {
      -- allow remote build/destory/upgrade
      name = "item-network-remote-action",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = true,
      order = "035",
    },
    {
      -- the number of entities to process per tick
      name = "item-network-config-entities-per-tick",
      type = "int-setting",
      setting_type = "runtime-global",
      default_value = 20,
      minimum_value = 1,
      order = "100",
    },
    {
      -- the number of priority queues
      name = "item-network-config-queue-count",
      type = "int-setting",
      setting_type = "runtime-global",
      default_value = 32,
      minimum_value = 2,
      maximum_value = 64,
      order = "101",
    },
    {
      -- the number of ticks per queue
      name = "item-network-config-queue-ticks",
      type = "int-setting",
      setting_type = "runtime-global",
      default_value = 20,
      minimum_value = 1,
      order = "102",
    },
    {
      name = "item-network-cheat-infinite-duplicate",
      type = "bool-setting",
      setting_type = "runtime-global",
      default_value = false,
      order = "900",
    },
  })
end
--[[

  - Option: personal logistics
  - Option: logistic chests
  - Option: alert/shortages
  - Option: furnace fuel, ingredients, output
  - Option: assembler fuel, ingredients, output
  - Option: car fuel, ammo
  - Option: car logistics
  - Option: spidertron logistics, ammo
  - Option: supply labs
  - Option: auto-build ghosts
  - Option: auto-destroy
  - Option: use cliff explosives

TODO: Can there be categories?
Or maybe I should do an in-game settings GUI?
  4 options for each category:
    - refuel
    - insert input items
    - remove output items
    - supply ammo
    - logistic requests

  Assembler: refuel, input, output
  Furnace: refuel, input, output
  Lab: refuel, input, output
  Car: refuel, ammo, logistic request
  Spidertron: refuel, ammo, logistic request
  Turret: refuel, ammo

]]
M.main()
