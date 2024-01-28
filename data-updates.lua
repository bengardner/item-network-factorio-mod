local constants = require'src.constants'



if mods["nullius"] then
  local all_items = {}
  all_items['network-loader'] = true
  --all_items['network-sensor'] = true
  --all_items['network-limit-sensor'] = true
  for k, _ in pairs(constants.NETWORK_TANK_NAMES) do
    all_items[k] = true
  end
  for k, _ in pairs(constants.NETWORK_CHEST_NAMES) do
    all_items[k] = true
  end

  for k, _ in pairs(all_items) do
    if data.raw.item[k] ~= nil then
      data.raw.item[k].order = "nullius-" .. k
      data.raw.recipe[k].order = "nullius-" .. k
    else
      print(string.format("*** did not find: %s", k))
    end
  end
end
