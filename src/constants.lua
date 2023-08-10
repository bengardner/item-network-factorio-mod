local M = {};

M.NUM_INVENTORY_SLOTS = 48
M.TANK_AREA = 50
M.TANK_HEIGHT = 1
M.MAX_TANK_SIZE = M.TANK_AREA * M.TANK_HEIGHT * 100

M.MAX_MISSING_TICKS = 5 * 60
M.ALERT_TRANSFER_TICKS = 5 * 60

return M
