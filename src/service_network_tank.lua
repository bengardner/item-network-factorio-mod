--[[
Service a network tank.
]]
local GlobalState = require "src.GlobalState"
local NetworkTankAutoConfig = require("src.NetworkTankAutoConfig")
local clog = require("src.log_console").log
local constants = require("src.constants")

--[[
Moves all fluid contents of the entity to the network.
]]
local function service_network_tank_provider(info)
  -- move all fluid into the network
  local fluid_instance = info.entity.fluidbox[1]
  if fluid_instance ~= nil then
    local key = GlobalState.fluid_temp_key_encode(fluid_instance.name, fluid_instance.temperature)
    local n_give = math.max(0, fluid_instance.amount)          -- how much we want to give
    local n_transfer
    if (info.config.no_limit == true) then
      n_transfer = n_give
    else
      local current_count = GlobalState.get_fluid_count(
        fluid_instance.name,
        fluid_instance.temperature
      )
      local gl_limit = GlobalState.get_limit(key)
      local n_take = math.max(0, gl_limit - current_count)       -- how much the network can take
      n_transfer = math.min(n_give, n_take)
    end
    if n_transfer > 0 then
      local n_removed = info.entity.remove_fluid({
        name = fluid_instance.name,
        temperature = fluid_instance.temperature,
        amount = n_transfer,
      })
      GlobalState.increment_fluid_count(fluid_instance.name,
        fluid_instance.temperature, n_removed)

      if n_removed > constants.MAX_TANK_SIZE * 0.75 then
        -- sent more than 75% of the tank, so raise the priority
        return GlobalState.UPDATE_STATUS.UPDATE_PRI_INC
      elseif n_removed < constants.MAX_TANK_SIZE * 0.25 then
        -- sent less than 25% of the tank, so lower the priority
        return GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC
      else
        -- between 25-75%. still good.
        return GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
      end
    end
  end
  -- did not send anything, so lower the priority
  return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
end

--[[
Request fluid to fill the tank.

buffer tuning logic:
 - prefer to tune via buffer level
 - track level at start of service (minumum level)
 - track how much is added on average
 -

  - if the average add doesn't change more than 10% then set the buffer to average_add * 1.2
  - if the average add > 90% then double the buffer size

]]
local function service_network_tank_requester(info)
  local entity = info.entity
  local config = info.config or {}

  -- NOTE: the network-tank has exactly 1 fluidbox, which may have a nil fluid
  -- hook in autoconfig
  if config.type == "auto" then
    local auto_config = NetworkTankAutoConfig.auto_config(entity)
    if auto_config == nil then
      return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
    end
    info.config = auto_config
    config = auto_config
  end
  if config.type ~= "take" then
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  local limit = config.limit or 5000
  local buffer = config.buffer or 1000
  local fluid = config.fluid
  local temp_exact = config.temperature
  local temp_min = config.minimum_temperature
  local temp_max = config.maximum_temperature
  local fluidbox = entity.fluidbox
  local status = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC -- SAME

  -- We are requesting fluid FROM the network
  local tank_fluid = nil
  local tank_temp = nil
  local tank_count = 0
  local n_fluid_boxes = 0

  for idx = 1, #fluidbox do
    local fluid_instance = fluidbox[idx]
    if fluid_instance ~= nil then
      n_fluid_boxes = n_fluid_boxes + 1
      tank_fluid = fluid_instance.name
      tank_temp = fluid_instance.temperature
      tank_count = fluid_instance.amount
    end
  end

  -- assume full service period if not doing a full request
  if tank_count < constants.MAX_TANK_SIZE then
    status = GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  -- clear the fluid if it doesn't match the config
  if n_fluid_boxes == 1 and tank_count > 0 and (
    tank_fluid ~= fluid or
    not GlobalState.fluid_temp_matches(tank_temp, temp_exact, temp_min, temp_max))
  then
    GlobalState.increment_fluid_count(tank_fluid, tank_temp, tank_count)
    entity.clear_fluid_inside()
    n_fluid_boxes = 0
    tank_count = 0
  end

  -- find a matching fluid
  local net_count, net_temp = GlobalState.get_fluid_count_range(fluid, temp_exact, temp_min, temp_max)

  -- only touch if there is a matching fluid
  -- local network_count = GlobalState.get_fluid_count(fluid, temp)
  config.ave_added = nil

  -- how much we the network can give us, less the limit
  local n_give = math.max(0, net_count - limit)
  local n_take = math.max(0, buffer - tank_count) -- how much space we have in the tank
  local n_transfer = math.floor(math.min(n_give, n_take))
  local new_tank_count = tank_count
  if n_transfer > 0 then
    local added = entity.insert_fluid({
      name = fluid,
      amount = n_transfer,
      temperature = net_temp,
    })
    if added > 0 then
      GlobalState.increment_fluid_count(fluid, net_temp, -added)
      new_tank_count = new_tank_count + added
    end
  end

  -- calculate the average fluid used
  local usage = 0
  if config.fluid_last ~= nil and config.fluid_last.name == fluid then
    usage = math.floor(math.max(0, config.fluid_last.count - tank_count))
    config.ave_usage = math.floor(((config.ave_usage or 0) + usage) / 2)
  else
    config.ave_usage = 0
  end
  config.fluid_last = { name=fluid, count=math.floor(new_tank_count) }
  local usage_err = math.floor(math.abs(usage - config.ave_usage)) / math.max(100, config.ave_usage)

  --[[
  print(string.format("[%s] %s added=%s usage=%s [%s] e=%s", entity.unit_number, entity.name,
    new_tank_count - tank_count,
    usage, math.floor(config.ave_usage), usage_err))
  ]]

  -- if we wanted more than was available
  if n_take > n_give then
    -- register missing only if we don't have any
    if tank_count < 1000 then
      -- FIXME: missing
      GlobalState.missing_fluid_set(fluid, temp_exact, temp_min, temp_max, info.entity.unit_number, n_take - n_give)
    end
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  --[[
  If the average amount added is > 90% buffer, then increase the buffer size
  ]]

  -- if we have more than we want, then don't service for a bit
  if tank_count > buffer then
    -- REVISIT: return extra to net?
    return GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
  end

  --[[
  If we are at the max tank size, then we can only adjust the priority.
  If the priority hits max, then we might be able to reduce the buffer size.

  If we are using/refilling more than 90%, then increase the buffer size by 2x.
  If the usage error is less than 20%, then set the buffer to 1000 + ave_usage.

  ]]

  if buffer == constants.MAX_TANK_SIZE then
    -- at max size: play with priorities
    if tank_count < buffer * 0.1 then
      -- had less than 10%, so inc the pri by 1
      status = GlobalState.UPDATE_STATUS.UPDATE_PRI_INC

    elseif tank_count > buffer * 0.5 then
      -- had over 50%, so dec the pri by 5
      status = 5

      -- if already at max pri AND had more than 50%, then reduce buffer size
      if info.service_priority == constants.MAX_PRIORITY and
         tank_count > buffer * 0.5
      then
        info.config.buffer = math.floor(buffer * 0.75)
      else
        --[[ print(string.format("[%s] %s NOPE max-pri=%s tc=%s buf=%s", entity.unit_number, entity.name,
        GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX,
        tank_count,
        buffer))
        ]]
      end

    elseif tank_count > buffer * 0.3 then
      -- had more than 30%, so dec the pri by 1
      status = GlobalState.UPDATE_STATUS.UPDATE_PRI_DEC

    else
      -- had 10% - 30% : that's OK
      status = GlobalState.UPDATE_STATUS.UPDATE_PRI_SAME
    end

  else
    -- not at full buffer size, so play with the buffer size
    status = GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
    if tank_count < 1000 then
      -- We were low, so double the buffer
      info.config.buffer = math.floor(math.min(buffer + math.max(buffer, 1000), constants.MAX_TANK_SIZE))
      --print(string.format("[%s] %s -> +++ buf %s => %s", entity.unit_number, entity.name, buffer, info.config.buffer))

    elseif usage_err < 0.05 then -- and config.ave_usage < buffer * 0.5 then
      -- using less than 30%, so we could decrease buffer
      status = GlobalState.UPDATE_STATUS.UPDATE_PRI_MAX
      info.config.buffer = math.floor(math.min(constants.MAX_TANK_SIZE, 1000 + config.ave_usage * 1.4))
      --print(string.format("[%s] %s -> --- buf %s => %s", entity.unit_number, entity.name, buffer, info.config.buffer))
    end
  end

  return status
end

local function service_network_tank(info)
  if info.config.type == "give" then
    return service_network_tank_provider(info)
  end
  return service_network_tank_requester(info)
end

local function create_network_tank(entity, tags)
  local config = nil
  if tags ~= nil then
    local config_tag = tags.config
    if config_tag ~= nil then
      config = config_tag
    end
  end
  GlobalState.register_tank_entity(entity, config)
end

-- clone is called with the info for both src and dest. same entity name.
local function clone_network_tank(dst_info, src_info)
  dst_info.config = table.deepcopy(src_info.config)
end

-------------------------------------------------------------------------------
-- register entity handlers

GlobalState.register_service_task("network-tank", {
  service=service_network_tank,
  create=create_network_tank,
  clone=clone_network_tank,
  tag="config",
})
GlobalState.register_service_task("network-tank-provider", {
  service=service_network_tank_provider,
  create=create_network_tank,
  clone=clone_network_tank,
  tag="config",
})
GlobalState.register_service_task("network-tank-requester", {
  service=service_network_tank_requester,
  create=create_network_tank,
  clone=clone_network_tank,
  tag="config",
})
