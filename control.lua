if script.active_mods["gvv"] then require("__gvv__.gvv")() end

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
