local NetworkChest = require "src.NetworkChest"
local TestGui = require "src.NetworkViewUi_test"
local UiHandlers = require "src.UiHandlers"
local EventDispatch = require "src.EventDispatch"

local function main()
  -- create
  EventDispatch.on_event(
    defines.events.on_built_entity,
    NetworkChest.on_built_entity
  )
  EventDispatch.on_event(
    defines.events.script_raised_built,
    NetworkChest.script_raised_built
  )
  EventDispatch.on_event(
    defines.events.on_entity_cloned,
    NetworkChest.on_entity_cloned
  )
  EventDispatch.on_event(
    defines.events.on_robot_built_entity,
    NetworkChest.on_robot_built_entity
  )
  EventDispatch.on_event(
    defines.events.script_raised_revive,
    NetworkChest.script_raised_revive
  )

  -- delete
  EventDispatch.on_event(
    defines.events.on_pre_player_mined_item,
    NetworkChest.generic_destroy_handler
  )
  EventDispatch.on_event(
    defines.events.on_robot_mined_entity,
    NetworkChest.generic_destroy_handler
  )
  EventDispatch.on_event(
    defines.events.script_raised_destroy,
    NetworkChest.generic_destroy_handler
  )
  EventDispatch.on_event(
    defines.events.on_entity_died,
    NetworkChest.on_entity_died
  )
  EventDispatch.on_event(
    defines.events.on_marked_for_deconstruction,
    NetworkChest.on_marked_for_deconstruction
  )


  EventDispatch.on_event(
    defines.events.on_post_entity_died,
    NetworkChest.on_post_entity_died
  )


  EventDispatch.on_event(
    defines.events.on_entity_settings_pasted,
    NetworkChest.on_entity_settings_pasted
  )


  EventDispatch.on_event(
    defines.events.on_player_setup_blueprint,
    NetworkChest.on_player_setup_blueprint
  )

  -- gui events
  EventDispatch.on_event(
    defines.events.on_gui_click,
    NetworkChest.on_gui_click
  )
  EventDispatch.on_event(
    defines.events.on_gui_opened,
    NetworkChest.on_gui_opened
  )
  EventDispatch.on_event(
    defines.events.on_gui_closed,
    NetworkChest.on_gui_closed
  )
  EventDispatch.on_event(
    defines.events.on_gui_text_changed,
    NetworkChest.on_gui_text_changed
  )
  EventDispatch.on_event(
    defines.events.on_gui_elem_changed,
    NetworkChest.on_gui_elem_changed
  )
  EventDispatch.on_event(
    defines.events.on_gui_checked_state_changed,
    NetworkChest.on_gui_checked_state_changed
  )
  EventDispatch.on_event(
    defines.events.on_gui_confirmed,
    NetworkChest.on_gui_confirmed
  )
  EventDispatch.on_event(
    defines.events.on_gui_selected_tab_changed,
    NetworkChest.on_gui_selected_tab_changed
  )
  EventDispatch.on_event(
    defines.events.on_gui_selection_state_changed,
    NetworkChest.on_gui_selection_state_changed
  )

  -- custom events
  script.on_event(
    "in_confirm_dialog",
    NetworkChest.in_confirm_dialog
  )
  script.on_event(
    "in_cancel_dialog",
    NetworkChest.in_cancel_dialog
  )
  script.on_event(
    "in_open_network_view",
    NetworkChest.in_open_network_view
  )
  script.on_event(
    "in_open_test_view",
    TestGui.in_open_test_view
  )

  script.on_nth_tick(1, NetworkChest.onTick)
  script.on_nth_tick(60, NetworkChest.onTick_60)
  -- script.on_nth_tick(60 * 3, NetworkChest.on_every_5_seconds)

  script.on_init(function()
    NetworkChest.on_init()
  end)
end

main()
