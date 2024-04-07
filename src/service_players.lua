local GlobalState = require "src.GlobalState"
local Event = require('__stdlib__/stdlib/event/event')
local clog = require("src.log_console").log


local function update_player(player, enable_logistics)
  local enable_player = settings.get_player_settings(player.index)["item-network-player-enable-logistics"].value

  local entity = player.character
  if entity == nil then
    return
  end

  if enable_logistics and not entity.force.character_logistic_requests then
    entity.force.character_logistic_requests = true
    if entity.force.character_trash_slot_count < 10 then
      entity.force.character_trash_slot_count = 10
    end
  end

  if enable_player then
    -- put all trash into network
    GlobalState.put_inventory_in_network(player.get_inventory(defines.inventory.character_trash))

    -- get contents of player inventory
    local main_inv = player.get_inventory(defines.inventory.character_main)
    if main_inv ~= nil then
      local character = player.character
      if character ~= nil and character.character_personal_logistic_requests_enabled then
        local main_contents = main_inv.get_contents()
        local cursor_stack = player.cursor_stack
        if cursor_stack ~= nil and cursor_stack.valid_for_read then
          main_contents[cursor_stack.name] = (main_contents[cursor_stack.name] or 0) + cursor_stack.count
        end

        -- scan logistic slots and transfer to character
        for logistic_idx = 1, character.request_slot_count do
          local param = player.get_personal_logistic_slot(logistic_idx)
          if param ~= nil and param.name ~= nil then
            local available_in_network = GlobalState.get_item_count(param.name)
            local current_amount = main_contents[param.name] or 0
            local delta = math.min(available_in_network,
            math.max(0, param.min - current_amount))
            if delta > 0 then
              local n_transfered = main_inv.insert({
                name = param.name,
                count = delta,
              })
              GlobalState.set_item_count(
                param.name,
                available_in_network - n_transfered
              )
            end
          end
        end
      end
    end
  end
end

local function service_players()
  local enable_logistics = settings.global["item-network-player-force-logistics"].value

  for _, player in pairs(game.players) do
    update_player(player, enable_logistics)
  end
end

Event.on_nth_tick(60, service_players)
