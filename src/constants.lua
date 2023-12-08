local M = {};

M.NUM_INVENTORY_SLOTS = 48
M.TANK_AREA = 1000
M.TANK_HEIGHT = 1
M.MAX_TANK_SIZE = M.TANK_AREA * M.TANK_HEIGHT * 100

M.ALERT_TRANSFER_TICKS = 10 * 60
M.MAX_MISSING_TICKS = 30 * 60
-- FIXME: now that the service queue takes so long, I need to 'cancel' a missing item when satisfied

-- use an array of queues, each must take a minimum of QUEUE_TICKS to process.
M.QUEUE_TICKS = 20
M.QUEUE_COUNT = 32
M.QUEUE_PERIOD_MIN = M.QUEUE_TICKS * M.QUEUE_COUNT

-- has to be small enough to be in the constant combinator, which uses 32-bit signed integers
M.UNLIMITED = 2000000000 -- "2G"

M.NETWORK_TANK_NAMES = {
  ["network-tank"] = "no", -- not created by network-tanks.lua
  ["network-tank-requester"] = true, -- from network to pipes
  ["network-tank-provider"] = false, -- from pipes to network
  }

return M
