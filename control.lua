if script.active_mods["gvv"] then require("__gvv__.gvv")() end

-- declare global
clog = require("src.log_console").log

-- need to register for on_tick() first
require "src.GlobalState"

require "src.NetworkChest"
require "src.NetworkSensor"
require "src.NetworkViewUi"
require "src.NetworkViewUi_test"
require "src.NetworkTankGui"

require "src.service_players"
require "src.service_alerts"
require "src.service_queue"
require "src.service_ghost"
require "src.auto_player_request"
