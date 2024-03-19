--[[
Automatically adds a 1-stack request for any researched items.
]]
local Event = require('__stdlib__/stdlib/event/event')
local item_utils = require("src.item_utils")
local clog = require("src.log_console").log

local function sort_character_requests(player, character, items, valid_items)
  local requests = {}
  local hit = {}
  for idx=1, character.request_slot_count do
    local ls = character.get_personal_logistic_slot(idx)
    if ls ~= nil and ls.name ~= nil then
      local da_max = ls.max
      if da_max > 1000000 then
        local iprot = game.item_prototypes[ls.name]
        if iprot ~= nil then
          da_max = iprot.stack_size
        end
      end
      if valid_items[ls.name] ~= nil then
        table.insert(requests, { slot=idx, item=ls.name, min=ls.min, max=da_max })
        hit[ls.name] = true
      end
    end
  end

  do
    local idx = character.request_slot_count
    for _, ic in ipairs(items) do
      if hit[ic.item] == nil then
        hit[ic.item] = true
        idx = idx + 1
        table.insert(requests, { slot=idx, item=ic.item, min=ic.count, max=ic.count, new=true })
      end
    end
  end
  --print(serpent.block(requests))

  table.sort(requests, item_utils.entry_compare_items)
  requests = item_utils.entry_list_split_by_group(requests)

  local add_idx = 1
  for _, rr in ipairs(requests) do
    if rr == 'break' then
      local old_idx = add_idx
      add_idx = 1 + math.floor((add_idx + 8) / 10) * 10
      for idx=old_idx, add_idx -1 do
        character.clear_personal_logistic_slot(idx)
      end
    else
      -- request exists -- do not touch if in the same slot
      if rr.slot ~= add_idx then
        if rr.slot > add_idx then
          character.clear_personal_logistic_slot(rr.slot)
        end
        character.clear_personal_logistic_slot(add_idx)
        character.set_personal_logistic_slot(add_idx, { name=rr.item, min=rr.min, max=rr.max })
      else
        -- same index (no change)
        character.clear_personal_logistic_slot(add_idx)
        character.set_personal_logistic_slot(add_idx, { name=rr.item, min=rr.min, max=rr.max })
      end
      add_idx = add_idx + 1
    end
  end
  for idx=add_idx, character.request_slot_count do
    character.clear_personal_logistic_slot(idx)
  end
end

local function set_character_requests(player, character, items)
  local requests = {}
  for name, count in pairs(items) do
    requests[name] = { slot=0, name=name, min=count, max=count }
  end
  for idx=1, character.request_slot_count do
    local ls = character.get_personal_logistic_slot(idx)
    if ls ~= nil and ls.name ~= nil then
      if ls.max > 1000000 then
        local iprot = game.item_prototypes[ls.name]
        if iprot ~= nil then
          ls.max = iprot.stack_size
        end
      end
      --print(string.format("old [%s] = %s", idx, serpent.line(rr)))
      requests[ls.name] = { slot=idx, name=ls.name, min=ls.min, max=ls.max } -- fields: name, min, max
    end
  end

  table.sort(items, item_utils.entry_compare_items)

  local thelist = item_utils.entry_list_split_by_group(items)

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
        character.clear_personal_logistic_slot(idx)
      end
    else
      local item = info.item
      local count = info.count
      local rr = requests[item]
      if rr ~= nil then
        requests[item] = nil
        -- request exists -- do not touch if in the same slot
        if rr.slot ~= add_idx then
          if rr.slot > add_idx then
            character.clear_personal_logistic_slot(rr.slot)
          end
          character.clear_personal_logistic_slot(add_idx)
          character.set_personal_logistic_slot(add_idx, { name=item, min=rr.min, max=rr.max })
        end
      else
        character.clear_personal_logistic_slot(add_idx)
        character.set_personal_logistic_slot(add_idx, { name=item, min=count, max=count })
      end
      add_idx = add_idx + 1
    end
  end
  for _, rr in pairs(requests) do
    print(string.format("ADD: %s @ %s", serpent.line(rr), add_idx))
    character.clear_personal_logistic_slot(add_idx)
    character.set_personal_logistic_slot(add_idx, { name=rr.name, min=rr.min, max=rr.max })
    add_idx = add_idx + 1
  end
  for idx=add_idx, character.request_slot_count do
    character.clear_personal_logistic_slot(idx)
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
        -- print(string.format(" -- Added %s due to %s [%s] %s", name, recipe.name, what, serpent.line(prot.localised_name)))
        --[[
        local pr = prot.place_result
        if pr ~= nil then
          local nup_name
          local nup = pr.next_upgrade
          if nup ~= nil then
            nup_name = nup.name
          end
          --print(string.format("   => place %s next_upgrade %s", pr.name, serpent.line(nup_name)))
        end
        ]]
      end
    end
  end

  --[[
  can't do all items, as we need to know if they are researched
  for _, prot in pairs(game.item_prototypes) do
    if prot.valid then
      if prot.place_as_tile_result ~= nil then
        print(string.format(" -- Added %s due to place_as_tile [%s]", prot.name, serpent.line(prot.place_as_tile_result.result.name)))
        table.insert(items, { item = prot.name, count = prot.stack_size })

      elseif prot.place_result ~= nil then
        print(string.format(" -- Added %s due to place_as_entity [%s]", prot.name, serpent.line(prot.place_result.name)))
        table.insert(items, { item = prot.name, count = prot.stack_size })
      end
    end
  end
  ]]

  for _, recipe in pairs(force.recipes) do
    --print(string.format("RECIPE: %s enabled=%s hidden=%s products=%s inf=%s", recipe.name, recipe.enabled, recipe.hidden, serpent.line(recipe.products), serpent.line(recipe.ingredients)))
    if recipe.enabled == true and recipe.hidden ~= true then
      for _, pp in ipairs(recipe.products) do
        add_item(pp.name, recipe, 'product')
      end
      --[[ this gets too many items, especially if there is a 'scrap' recipe
      ]]
      for _, pp in ipairs(recipe.ingredients) do
        if pp.type == "item" then
          add_item(pp.name, recipe, 'ingredients')
        end
      end
    end
  end

  table.sort(items, item_utils.entry_compare_items)

  --items = item_utils.entry_list_split_by_group(items)

  for _, player in ipairs(force.players) do
    local character = player.character
    if character ~= nil and player.character_personal_logistic_requests_enabled then
      --set_character_requests(player, character, items)
      sort_character_requests(player, character, items, items_tab)
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
