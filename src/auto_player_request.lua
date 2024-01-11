--[[
Automatically adds a 1-stack request for any researched items.
]]
local Event = require('__stdlib__/stdlib/event/event')
local item_utils = require("src.item_utils")
local clog = require("src.log_console").log

local function set_character_requests(player, character, items)
  local requests = {}
  for idx=1, character.request_slot_count do
    local rr = character.get_request_slot(idx)
    if rr ~= nil then
      --print(string.format("old [%s] = %s", idx, serpent.line(rr)))
      requests[rr.name] = { count=rr.count, slot=idx }
    end
  end

  --print("\nitems:")
  --print(serpent.block(items))

  -- always add to the end for now
  -- TODO: restructure to match the inventory list (break on groups)
  local add_idx = 1
  for _, info in ipairs(items) do
    if info == 'break' then
      local old_idx = add_idx
      add_idx = 1 + math.floor((add_idx + 8) / 10) * 10
      for idx=old_idx, add_idx -1 do
        character.clear_request_slot(idx)
      end
    else
      local item = info.item
      local count = info.count
      local rr = requests[item]
      if rr ~= nil then
        -- request exists -- do not touch if in the same slot
        if rr.slot ~= add_idx then
          if rr.slot > add_idx then
            character.clear_request_slot(rr.slot)
          end
          character.clear_request_slot(add_idx)
          character.set_request_slot({ name=item, count=math.max(1, rr.count) }, add_idx)
        end
      else
        character.clear_request_slot(add_idx)
        character.set_request_slot({name=item, count=count}, add_idx)
      end
      add_idx = add_idx + 1
    end
  end
  for idx=add_idx, character.request_slot_count do
    character.clear_request_slot(idx)
  end
end

local function force_request_everything(force)
  -- get all items that have a valid recipe and the stack size for each
  local items_tab = {}
  local items = {}
  local function add_item(name, recipe, what)
    if items_tab[name] == nil then
      -- this filters out fluids
      local prot = game.item_prototypes[name]
      if prot ~= nil then
        items_tab[name] = true
        table.insert(items, { item = name, count = prot.stack_size })
        -- print(string.format(" -- Added %s due to %s [%s]", name, recipe.name, what))
      end
    end
  end
  for _, recipe in pairs(force.recipes) do
    --print(string.format("RECIPE: %s enabled=%s hidden=%s products=%s inf=%s", recipe.name, recipe.enabled, recipe.hidden, serpent.line(recipe.products), serpent.line(recipe.ingredients)))
    if recipe.enabled == true and recipe.hidden ~= true then
      for _, pp in ipairs(recipe.products) do
        add_item(pp.name, recipe, 'product')
      end
      --[[ this gets too many items, especially if there is a 'scrap' recipe
      for _, pp in ipairs(recipe.ingredients) do
        if pp.type == "item" then
          add_item(pp.name, recipe, 'ingredients')
        end
      end
      ]]
    end
  end
  table.sort(items, item_utils.entry_compare_items)

  items = item_utils.entry_list_split_by_group(items)

  for _, player in ipairs(force.players) do
    local character = player.character
    if character ~= nil and player.character_personal_logistic_requests_enabled then
      set_character_requests(player, character, items)
    end
  end
end

local function on_research_stuff(event)
  local research = event.research
  if research ~= nil and research.force ~= nil then
    force_request_everything(research.force)
  end
end

Event.on_event(defines.events.on_research_finished, on_research_stuff)
Event.on_event(defines.events.on_research_reversed, on_research_stuff)

local M = {}

function M.doit(player)
  force_request_everything(player.force)
end

return M
