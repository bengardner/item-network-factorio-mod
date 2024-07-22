local GUIModButton = {}

local NetworkViewUI = require "src.NetworkViewUi"
local Event = require('__stdlib__/stdlib/event/event')

-- this is from the factorio source
local mod_gui = require "mod-gui"

local Util = require "src.Util"
local GUIDispatcher = require "src.GUIDispatcher"
local R = require "src.RichText"
--local EntityManager = require "src.EntityManager"
local GUICommon = require "src.GUICommon"
--local GUIItemPriority = require "src.GUIItemPriority"

local TICKS_PER_UPDATE = 30
local BUTTON_NAME = "cin-mod-btn"

local function update_gui(player)
  local button_frame = mod_gui.get_button_flow(player)
  local button = button_frame[BUTTON_NAME]
  if button == nil then
    button = button_frame.add({
      type = "sprite-button",
      name = BUTTON_NAME,
      sprite = "cin-logo",
      tags = { event = BUTTON_NAME }
    })
  end

  local enabled = global.forces[player.force.name] ~= nil
  if enabled then
    button.tooltip = {
      "",
      "Auto Resource Redux: ",
      R.LABEL,
      { "gui-mod-info.status-enabled" },
      R.LABEL_END,
      "\n",
      R.HINT,
      { "control-keys.mouse-button-1" },
      R.HINT_END,
      " to set item priorities.",
    }
    button.sprite = "cin-logo"
  else
    button.tooltip = {
      "",
      "Auto Resource Redux: ",
      R.LABEL,
      { "gui-mod-info.status-disabled" },
      R.LABEL_END,
      "\n",
      R.HINT,
      { "control-keys.mouse-button-1" },
      R.HINT_END,
      " to enable.",
    }
    button.sprite = "cin-logo-disabled"
  end
end

function GUIModButton.on_tick()
  local _, player = Util.get_next_updatable("logo_button_gui", TICKS_PER_UPDATE, game.connected_players)
  if player then
    update_gui(player)
  end
end

local function enable_mod_for_force(player)
  local enabled = global.forces[player.force.name] ~= nil
  if enabled then
    return false
  end

  game.print(
    ("%sAuto Resource Redux%s: %s enabled the mod for force \"%s\""):format(
      R.COLOUR_LABEL,
      R.COLOUR_END,
      R.get_coloured_text(player.chat_color, player.name),
      player.force.name
    )
  )
  player.force.print("Welcome back, commander!")
  global.forces[player.force.name] = true
  EntityManager.reload_entities()
  update_gui(player)
  return true
end

local function on_button_click(event, tags, player)
  local click_str = GUICommon.get_click_str(event)
  if click_str == "left" then
    log("Clicked the MOD button")
    NetworkViewUI.open_main_frame(event.player_index)
    -- clicked on the button
    --if not enable_mod_for_force(player) then
    --  GUIItemPriority.open(player)
    --end
  end
end

GUIDispatcher.register(defines.events.on_gui_click, BUTTON_NAME, on_button_click)

Event.on_nth_tick(TICKS_PER_UPDATE, GUIModButton.on_tick)

return GUIModButton
