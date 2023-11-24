--[[
Some helpers for managing the UI persistant data.

At the top of the UI file, do something like:
  M.mgr = GuiManager.new("my_unique_tag")
]]
local GlobalState = require "src.GlobalState"
local clog = require("src.log_console").log

local GuiManager = {}
function GuiManager.new(name)
  local self = { name=name }
  return setmetatable(self, { __index = GuiManager })
end

function GuiManager:get(player_index)
  return GlobalState.get_ui_state(player_index)[self.name]
end

function GuiManager:set(player_index, value)
  GlobalState.get_ui_state(player_index)[self.name] = value
end

function GuiManager:destroy(player_index)
  local ui = GlobalState.get_ui_state(player_index)
  local inst = ui[self.name]
  if inst ~= nil then
    -- break the link to prevent future events
    ui[self.name] = nil

    -- call destructor on any child classes
    if type(inst.children) == 'table' then
      for _, ch in pairs(inst.children) do
        if type(ch.destroy) == "function" then
          ch.destroy(ch)
        end
      end
    end

    if inst.elems ~= nil and inst.elems.main_window ~= nil then
      -- remove player focus
      local player = inst.player or game.get_player(player_index)
      if player ~= nil and player.opened == inst.elems.main_window then
        player.opened = nil
      end

      -- destroy the UI
      inst.elems.main_window.destroy()
    end
  end
end

-- returns a function that can be attached to an event
function GuiManager:wrap(func)
  -- callback takes an event, calls get() and passes that to the function
  return function (event)
    local inst = self:get(event.player_index)
    --clog("wrap event %s", serpent.line(inst))
    if inst ~= nil then
      func(inst, event)
    end
  end
end

--[[
Creates a new top-level window and returns the table of elements.
This sets the window as the current
  @player is the player that gets the GUI
  @title is the name to put in the title bar
  @opts selects the extra buttons to enable
    'window_name' = unqiue name for the window (uses title if omitted)
    'refresh_button' = unique name for the refresh button (not created if omitted)
    'close_button' = unique name for the close button (not created if omitted)
    'pin_button' = unique name for the pin button (not created if omitted)

  retval.elems.body is set to a vertical flow where the GUI elements should be added.
]]
function GuiManager:create_window(player, title, opts)
  local elems = {}

  -- create the main window
  local main_window = player.gui.screen.add({
    type = "frame",
    name = opts.window_name or title,
    style = "inset_frame_container_frame",
  })
  main_window.auto_center = true
  main_window.style.horizontally_stretchable = true
  main_window.style.vertically_stretchable = true
  elems.main_window = main_window

  -- create a vertical flow to cover the entire window body
  local vert_flow = main_window.add({
    type = "flow",
    direction = "vertical",
  })
  vert_flow.style.horizontally_stretchable = true
  vert_flow.style.vertically_stretchable = true

  -- add the header/toolbar flow
  local title_flow = vert_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  title_flow.drag_target = main_window
  elems.title_flow = title_flow

  -- add the window title
  title_flow.add {
    type = "label",
    caption = title,
    style = "frame_title",
    ignored_by_interaction = true,
  }

  -- add the drag space
  local header_drag = title_flow.add {
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true,
  }
  header_drag.style.horizontally_stretchable = true
  header_drag.style.vertically_stretchable = true
  header_drag.style.height = 24

  local name = opts.refresh_button
  if name ~= nil then
    elems.refresh_button = title_flow.add {
      name = name,
      type = "sprite-button",
      sprite = "utility/refresh",
      style = "frame_action_button",
      tooltip = { "gui.refresh" },
    }
  end

  name = opts.close_button
  if name ~= nil then
    elems.close_button = title_flow.add {
      name = name,
      type = "sprite-button",
      sprite = "utility/close_white",
      hovered_sprite = "utility/close_black",
      clicked_sprite = "utility/close_black",
      style = "close_button",
    }
  end

  name = opts.pin_button
  if name ~= nil then
    elems.pin_button = title_flow.add {
      name = name,
      type = "sprite-button",
      sprite = "flib_pin_white",
      hovered_sprite = "flib_pin_black",
      clicked_sprite = "flib_pin_black",
      style = "frame_action_button",
    }
  end

  -- create the window body flow
  elems.body = vert_flow.add({
    type = "flow",
    direction = "vertical",
  })

  -- give focus to the window (make optional?)
  player.opened = main_window

  -- start the UI data
  local inst = {
    elems = elems,
    player = player,
    -- children = nil,
  }

  self:set(player.index, inst)

  return inst
end

return GuiManager
