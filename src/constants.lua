local M = {};

M.NUM_INVENTORY_SLOTS = 48
M.TANK_AREA = 1000
M.TANK_HEIGHT = 1
M.MAX_TANK_SIZE = M.TANK_AREA * M.TANK_HEIGHT * 100
M.DEFAULT_TANK_REQUEST = 1000

M.ALERT_TRANSFER_TICKS = 10 * 60
M.MAX_MISSING_TICKS = 30 * 60
-- FIXME: now that the service queue takes so long, I need to 'cancel' a missing item when satisfied

-- use an array of queues, each must take a minimum of QUEUE_TICKS to process.
M.QUEUE_TICKS = 20
M.QUEUE_COUNT = 32
M.QUEUE_PERIOD_MIN = M.QUEUE_TICKS * M.QUEUE_COUNT
M.MAX_PRIORITY = M.QUEUE_COUNT - 2

-- has to be small enough to be in the constant combinator, which uses 32-bit signed integers
M.UNLIMITED = 2000000000 -- "2G"

M.NETWORK_TANK_NAMES = {
 -- ["network-tank"] = { gui=true, type="input-output", base_level=0 },       -- configurable
  ["network-tank-requester"] = { gui=true, type="output", base_level=0.5 }, -- from network to pipes
  ["network-tank-provider"] = { gui=false, type="input", base_level=-0.5 }, -- from pipes to network
  }

M.NETWORK_CHEST_NAMES = {
  ["network-chest"] = true,
  ["network-chest-provider"] = false,
}

return M
