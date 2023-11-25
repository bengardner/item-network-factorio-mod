local M = {};

M.NUM_INVENTORY_SLOTS = 48
M.TANK_AREA = 100
M.TANK_HEIGHT = 1
M.MAX_TANK_SIZE = M.TANK_AREA * M.TANK_HEIGHT * 100

M.ALERT_TRANSFER_TICKS = 10 * 60
M.MAX_MISSING_TICKS = 5 * 60

-- use an array of queues, each must take a minimum of QUEUE_TICKS to process.
M.QUEUE_COUNT = 10
M.QUEUE_TICKS = 10 -- should be like 10

-- has to be small enough to be in the constant combinator
M.UNLIMITED = 2000000000 -- "2G"

M.NETWORK_TANK_NAMES = {
  ["network-tank"] = "no", -- not created by network-tanks.lua
  ["network-tank-requester"] = true, -- from network to pipes
  ["network-tank-provider"] = false, -- from pipes to network
  }

return M
