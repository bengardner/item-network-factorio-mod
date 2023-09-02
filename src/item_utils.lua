--[[
Some common utilites for manipulating item list or the UI.
]]
local clog = require("src.log_console").log

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
function M.item_need_group_break(p1, p2, break_fluids)
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
    return break_fluids and (p1 ~= p2)
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
  if left_order == right_order then
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
  -- fluids are first
  local left_f_proto = game.fluid_prototypes[left.item]
  local right_f_proto = game.fluid_prototypes[right.item]
  if left_f_proto ~= nil then
    if right_f_proto ~= nil then
      return M.entry_compare_fluids(left, right)
    end
    -- fluids before items
    return true
  end

  -- items are last
  local left_i_proto = game.item_prototypes[left.item]
  local right_i_proto = game.item_prototypes[right.item]
  if left_i_proto ~= nil and right_i_proto ~= nil then
      return M.entry_compare_items(left, right)
  end

  return left.item < right.item
end

-- insert a string ("break") between items that are in different type/subgroups
function M.entry_list_split_by_group(items, break_fluid)
  local out_items = {}
  local last_item_name
  for _, item in ipairs(items) do
    if last_item_name ~= nil and M.item_need_group_break(last_item_name, item.item, break_fluid) then
      table.insert(out_items, "break")
    end
    table.insert(out_items, item)
    last_item_name = item.item
  end
  return out_items
end

function M.entry_compare_count(left, right)
  return left.count > right.count
end

function M.get_item_tooltip(name, count, template)
  assert(template ~= nil, "template cannot be nil")
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
      template,
      info.localised_name,
      count,
    }
  end
end

function M.get_item_plain_tooltip(item_name, item_count)
  return M.get_item_tooltip(item_name, item_count, "in_nv.item_plain_btn_tooltip")
end

function M.get_item_filter_tooltip(item_name, item_count)
  return M.get_item_tooltip(item_name, 0, "in_nv.item_filter_btn_tooltip")
end

function M.get_item_inventory_tooltip(item_name, item_count)
  return M.get_item_tooltip(item_name, item_count, "in_nv.item_sprite_btn_tooltip")
end

function M.get_item_char_inventory_tooltip(item_name, item_count)
  return M.get_item_tooltip(item_name, item_count, "in_nv.item_char_btn_tooltip")
end

function M.get_item_limit_tooltip(item_name, item_count)
  return M.get_item_tooltip(item_name, item_count, "in_nv.item_limit_btn_tooltip")
end

function M.get_item_shortage_tooltip(item_name, item_count)
  return M.get_item_tooltip(item_name, item_count, "in_nv.item_shortage_btn_tooltip")
end

function M.get_fluid_tooltip(name, temp, count, template)
  assert(template ~= nil, "template cannot be nil")
  local localised_name
  local info = game.fluid_prototypes[name]
  if info == nil then
    localised_name = name or "Unknown Fluid"
  else
    localised_name = info.localised_name
  end
  return {
    template,
    localised_name,
    string.format("%.0f", count),
    { "format-degrees-c", string.format("%.0f", temp) },
  }
end

function M.get_fluid_inventory_tooltip(name, temp, count)
  return M.get_fluid_tooltip(name, temp, count, "in_nv.fluid_sprite_btn_tooltip")
end

function M.get_fluid_limit_tooltip(name, temp, count)
  return M.get_fluid_tooltip(name, temp, count, "in_nv.fluid_limit_btn_tooltip")
end

function M.get_fluid_shortage_tooltip(name, temp, count)
  return M.get_fluid_tooltip(name, temp, count, "in_nv.fluid_sprite_btn_tooltip")
end

function M.filter_name_or_tag(event, pattern)
  if event.element and event.element.valid then
    if event.element.name == pattern or event.element.tags.event == pattern then
      return true
    end
  end
end

--[[
  Checks to see if an item stack can be stored in the item network.
  @stack should be a LuaItemStack.

  If the item cannot be stored, then this returns nil.
  If it can be stored, then it breaks the stack down into a list of simple stacks.

  If item_number is not nil, then the game tracks the item instance and it might not
  be storeable in the item network.

  NOTE: the game strips out inventory when converting an entity to an item.
  The "item-with-inventory" appears to be just the blueprint-book.

  According to the docs, item_number ~= nil for the following types:
    - "armor"                 -- can store after emptying the grid (loses label, colors, etc)
    - "spidertron-remote"     -- can store (loses connected_entity)
    - "selection-tool"        -- never store
    - "copy-paste-tool"       -- never store
    - "upgrade-item"          -- never store
    - "deconstruction-item"   -- never store
    - "blueprint"             -- never store
    - "blueprint-book"        -- never store
    - "item-with-entity-data" -- is_item_with_entity_data = can store after emptying the grid (loses label, colors)
    - "item-with-inventory"   -- never store (blueprint-book?)
    - "item-with-tags"        -- never store (never seen this)
]]
function M.breakdown_stack(stack)
  if not stack.valid_for_read then
    -- can't read it, so can't store it.
    return nil
  end
  local item_name = stack.name
  local prot = game.item_prototypes[item_name]
  if prot == nil then
    -- can only store defined items
    return nil
  end

  -- start with the stack item
  local stacks = { { name = item_name, count = stack.count} }

  -- only need to handle if tracked individually
  if stack.item_number ~= nil then
    -- We can break down armor, vehicles (item-with-entity-data), and remotes
    if not (stack.is_armor or stack.is_item_with_entity_data or stack.type == "spidertron-remote") then
      return nil
    end

    -- extract the grid contents
    if stack.grid then
      for name, count in pairs(stack.grid.get_contents()) do
        table.insert(stacks, { name=name, count=count })
      end
    end
  end

  return stacks
end

return M
