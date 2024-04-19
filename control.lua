if script.active_mods["gvv"] then require("__gvv__.gvv")() end

-- declare global 'clog'
clog = require("src.log_console").log

require "src.GlobalState"

require "src.NetworkChest"
require "src.NetworkSensor"
require "src.NetworkViewUi"
require "src.NetworkViewUi_test"
require "src.NetworkTankGui"

require "src.service_alerts"
require "src.service_assembling_machine"
require "src.service_car"
require "src.service_generic"
require "src.service_ghost"
require "src.service_furnace"
require "src.service_lab"
require "src.service_logistic_chest"
require "src.service_network_chest"
require "src.service_network_tank"
require "src.service_players"
require "src.service_rocket_silo"
require "src.service_spidertron"
require "src.service_upgrades"

require "src.auto_player_request"
require "src.cheat_production_supply"

require "src.remote_interface"
