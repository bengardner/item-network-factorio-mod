--[[
Some common utilites for manipulating item list or the UI.
]]
local log = require("src.log_console").log

local M = {}

-- adds empty items to fill the row (not really needed? better to add an empty widgit?)
function M.pad_item_table_row(item_table)
  --[[
  local blank_def = {
    type = "sprite",
    sprite = "inet_slot_empty_inset",
    ignored_by_interaction = true,
  }
  ]]
  local blank_def = { type = "empty-widget" }
  local column_count = item_table.column_count
  while #item_table.children % column_count > 0 do
    item_table.add(blank_def)
  end
end

--[[
  Check to see if the two items are in different subgroups.
]]
function M.item_need_group_break(p1, p2)
  if p1 == nil or p2 == nil then
    return true
  end
  local p1_f = game.fluid_prototypes[p1]
  local p2_f = game.fluid_prototypes[p2]
  local p1_i = game.item_prototypes[p1]
  local p2_i = game.item_prototypes[p2]

  if ((p1_f == nil) ~= (p2_f == nil)) or ((p1_i == nil) ~= (p2_i == nil)) then
    -- need a break between fluid and items
    return true
  end
  if (p1_f ~= nil) or (p2_f ~= nil) then
    -- fluids
    return false
  end
  if p1_i == nil or p2_i == nil then
    return true
  end
  return (p1_i.group.name ~= p2_i.group.name) or (p1_i.subgroup.name ~= p2_i.subgroup.name)
end

-- compare two fluidss by order then temperature
function M.entry_compare_fluids(left, right)
  local left_order = game.fluid_prototypes[left.item].order
  local right_order = game.fluid_prototypes[right.item].order
  if left_order == left_order then
    return left.temp < right.temp
  end
  return left_order < right_order
end

function M.entry_compare_items(left, right)
  local proto_left = game.item_prototypes[left.item]
  local proto_right = game.item_prototypes[right.item]

  if proto_left.group.order ~= proto_right.group.order then
    return proto_left.group.order < proto_right.group.order
  end
  if proto_left.subgroup.order ~= proto_right.subgroup.order then
    return proto_left.subgroup.order < proto_right.subgroup.order
  end
  return proto_left.order < proto_right.order
end

function M.entry_compare_group_order(left, right)
  -- the deposit slot is always first
  if left.is_deposit_slot then
    return true
  end
  if right.is_deposit_slot then
    return false
  end

  -- fluids are next
  local left_f_proto = game.fluid_prototypes[left.item]
  local right_f_proto = game.fluid_prototypes[right.item]
  if left_f_proto ~= nil then
    if right_f_proto ~= nil then
      return M.entry_compare_fluids(left, right)
    end
    return true
  end

  -- items are last
  local left_i_proto = game.item_prototypes[left.item]
  local right_i_proto = game.item_prototypes[right.item]
  if left_i_proto ~= nil and right_i_proto ~= nil then
      return M.entry_compare_items(left, right)
  end

  -- anything else is randomly thrown at the end
  return left_i_proto ~= nil
end

-- sort the list and insert a string ("break") between items that are in different subgroups
function M.entry_list_split_by_group(items)
  table.sort(items, M.entry_compare_group_order)
  local out_items = {}
  local last_item_name
  for _, item in ipairs(items) do
    if last_item_name ~= nil and M.item_need_group_break(last_item_name, item.item) then
      table.insert(out_items, "break")
    end
    table.insert(out_items, item)
    last_item_name = item.item
  end
  return out_items
end


function M.get_item_tooltip(name, count)
  local info = game.item_prototypes[name]
  if info == nil then
    return {
      "",
      name or "Unknown Item",
      ": ",
      count,
    }
  else
    return {
      "in_nv.item_sprite_btn_tooltip",
      info.localised_name,
      count,
    }
  end
end

function M.get_fluid_tooltip(name, temp, count)
  local localised_name
  local info = game.fluid_prototypes[name]
  if info == nil then
    localised_name = name or "Unknown Fluid"
  else
    localised_name = info.localised_name
  end
  return {
    "in_nv.fluid_sprite_btn_tooltip",
    localised_name,
    string.format("%.0f", count),
    { "format-degrees-c", string.format("%.0f", temp) },
  }
end

return M
