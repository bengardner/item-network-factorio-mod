--[[
Handles the following events:
 - on_marked_for_deconstruction()
 - on_cancelled_deconstruction()
 - on_marked_for_upgrade()
 - on_cancelled_upgrade()
]]
local GlobalState = require "src.GlobalState"
local Event = require('__stdlib__/stdlib/event/event')

local M = {}

function M.filter_list(the_list, func)
  local now = game.tick
  local do_later = {}
  local do_now = {}
  for _, ee in ipairs(the_list) do
    local ent = ee[1]
    if ent.valid and ent[func]() then
      if now >= ee[2] then
        table.insert(do_now, ee)
      else
        table.insert(do_later, ee)
      end
    end
  end
  return do_now, do_later
end

-------------------------------------------------------------------------------

function M.deconstruct_set(unum, val)
  if unum ~= nil then
    if global.to_deconstruct == nil then
      global.to_deconstruct = {}
    end
    global.to_deconstruct[unum] = val
  end
end

function M.deconstruct_add(entity)
  if entity ~= nil then
    local unum = entity.unit_number
    if unum ~= nil then
      local val = { entity, game.tick + 120 }
      M.deconstruct_set(unum, val)
    end
  end
end

function M.deconstruct_cancel(entity)
  if entity ~= nil then
    local unum = entity.unit_number
    if unum ~= nil then
      M.deconstruct_set(unum, nil)
    end
  end
end

function M.process_deconstruct()
  local do_now, do_later = M.filter_list(global.to_deconstruct, "to_be_deconstructed")
  global.to_deconstruct = do_later

  if #do_now > 0 then
    local inv = game.create_inventory(math.min(100, 4 * #do_now))
    for _, eee in ipairs(do_now) do
      local ent = eee[1]
      -- print(string.format("delayed mine %s @ %s", ent.name, serpent.line(ent.position)))
      ent.mine({ inventory=inv })
    end
    for name, count in pairs(inv.get_contents()) do
      M.increment_item_count(name, count)
    end
    inv.destroy()
  end
end

-------------------------------------------------------------------------------

--[[
Queue the entity to be handled in ~3 seconds.
]]
function M.on_marked_for_upgrade(event)
  local entity = event.entity
  if entity ~= nil and event.player_index ~= nil and entity.unit_number ~= nil then
    local val = { entity, event.tick + 180, event.player_index }

    if global.to_upgrade == nil then
      global.to_upgrade = {}
    end
    global.to_upgrade[entity.unit_number] = val
  end
end

-- drop entity immediately
function M.on_cancelled_upgrade(event)
  local entity = event.entity
  if entity ~= nil and entity.unit_number ~= nil then
    if global.to_upgrade ~= nil then
      global.to_upgrade[entity.unit_number] = nil
    end
  end
end

function M.process_upgrade()
  local now = game.tick
  local do_later = {}
  local do_now = {}

  -- revisit: could just do one pass and remove handled entries

  for unum, ee in pairs(global.to_upgrade or {}) do
    local ent = ee[1]
    if ent.valid and ent.to_be_upgraded() then
      if now >= ee[2] then
        do_now[unum] = ee
      else
        do_later[unum] = ee
      end
    end
  end
  global.to_upgrade = do_later

  for unum, eee in pairs(do_now) do
    local ent = eee[1]
    local player_index = eee[3]

    -- print(string.format("delayed mine %s @ %s", ent.name, serpent.line(ent.position)))
    local tprot = ent.get_upgrade_target()
    if tprot ~= nil then
      local name = tprot.name
      local n_avail = GlobalState.get_item_count(name)
      if n_avail > 0 then
        local dir = ent.get_upgrade_direction()
        if dir == nil then
          dir = ent.direction
        end
        local new_ent = ent.surface.create_entity({
          name = tprot.name,
          position = ent.position,
          direction = dir,
          force = ent.force,
          fast_replace = true,
          player = player_index,
          spill = true,
          raise_built = true,
        })
        if new_ent ~= nil then
          GlobalState.increment_item_count(name, -1)
          print(string.format("upgraded %s @ %s", new_ent.name, serpent.line(new_ent.position)))
        end
      else
        GlobalState.missing_item_set(name, ent.unit_number, 1)
        -- print(string.format("cannot upgrade %s @ %s", ent.name, serpent.line(ent.position)))
        eee[2] = now + 180
        global.to_upgrade[unum] = eee
      end
    end
  end
end

-------------------------------------------------------------------------------

function M.process()
  -- M.process_deconstruct()
  M.process_upgrade()
end

Event.on_event(
  defines.events.on_marked_for_upgrade,
  M.on_marked_for_upgrade
)

Event.on_event(
  defines.events.on_cancelled_upgrade,
  M.on_cancelled_upgrade
)

--[[
Event.on_event(
  defines.events.on_marked_for_deconstruction,
  M.on_marked_for_deconstruction
)

Event.on_event(
  defines.events.on_cancelled_deconstruction,
  M.on_cancelled_deconstruction
)
]]

Event.on_nth_tick(60, M.process)
