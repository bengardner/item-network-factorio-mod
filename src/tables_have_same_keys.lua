local M = {}

-- non-recursive comparison of the keys of two tables
function M.tables_have_same_keys(tab1, tab2)
  if tab1 == nil or tab2 == nil then
    return false
  end
  for k1, _ in pairs(tab1) do
    if tab2[k1] == nil then
      return false
    end
  end
  for k2, _ in pairs(tab2) do
    if tab1[k2] == nil then
      return false
    end
  end
  return true
end

-- compare two tables that consist of key=value
function M.tables_have_same_counts(tab1, tab2)
  if tab1 == nil or tab2 == nil then
    return false
  end
  for k1, v1 in pairs(tab1) do
    if tab2[k1] ~= v1 then
      return false
    end
  end
  for k2, v2 in pairs(tab2) do
    if tab1[k2] ~= v2 then
      return false
    end
  end
  return true
end

-- compare two flat tables that are iterated using pairs()
function M.same_pairs_flat(tab1, tab2)
  if tab1 == nil or tab2 == nil then
    return false
  end
  for k1, v1 in pairs(tab1) do
    if tab2[k1] ~= v1 then
      return false
    end
  end
  for k2, v2 in pairs(tab2) do
    if tab1[k2] ~= v2 then
      return false
    end
  end
  return true
end

function M.same_value(value1, value2)
  --print("comparing", serpent.block(value1), "vs", serpent.block(value2))
  -- both nil or different type => false
  if type(value2) ~= type(value1) or value1 == nil then
    --print(" - not same type or nil")
    return false
  end
  if type(value1) == "table" then
    --print(" - comparing tables")
    -- same type, both tables
    for k1, v1 in pairs(value1) do
      local v2 = value2[k1]
      if not M.same_value(v1, v2) then
        return false
      end
    end
    for k2, v2 in pairs(value2) do
      local v1 = value1[k2]
      if not M.same_value(v1, v2) then
        return false
      end
    end
    return true
  end
  -- same type, not a table
  return (value2 == value1)
end

-- compare two flat tables that are iterated using pairs()
function M.same_pairs_recursive(tab1, tab2)
  if tab1 == nil or tab2 == nil then
    return false
  end
  for k1, v1 in pairs(tab1) do
    local v2 = tab2[k1]
    if type(v2) ~= type(v1) then
      return false
    end
    if type(v1) == "table" then
      if not M.same_pairs_recursive(v1, v2) then
        return false
      end
    end
    if v2 ~= v1 then
      return false
    end
  end
  for k2, v2 in pairs(tab2) do
    if tab1[k2] ~= v2 then
      return false
    end
  end
  return true
end

return M
