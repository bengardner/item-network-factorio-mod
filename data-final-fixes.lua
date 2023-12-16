local M = {}

function M.main()
  M.add_network_chest_as_pastable_target_for_assemblers()
end

function M.add_network_chest_as_pastable_target_for_assemblers()
  for _, assembler in pairs(data.raw["assembling-machine"]) do
    local entities = assembler.additional_pastable_entities or {}
    table.insert(entities, "network-chest")
    table.insert(entities, "network-chest-provider")
    assembler.additional_pastable_entities = entities
  end
  for _, silo in pairs(data.raw["rocket-silo"]) do
    local entities = silo.additional_pastable_entities or {}
    table.insert(entities, "network-chest")
    silo.additional_pastable_entities = entities
  end
end

do
  local furnaces = {}
  for k, _ in pairs(data.raw['furnace']) do
    table.insert(furnaces, k)
  end
  for k, ff in pairs(data.raw['furnace']) do
    local entities = ff.additional_pastable_entities or {}
    for _, xx in ipairs(furnaces) do
      table.insert(entities, xx)
    end
    ff.additional_pastable_entities = entities
  end
end

M.main()
