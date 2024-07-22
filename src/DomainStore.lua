--[[
This provides per-domain storage helpers.

global.domains[domain_key][subdomain_key] = {}

The domain_key is currently just the force name.
No surface separation.
]]
local DomainStore = {}

--[[ Whether surfaces are kept separate.
REVISIT: If wanted, this should be a map(?) setting.
Would need to add support for combining or splitting surface storage.
]]
local separate_surfaces = false

function DomainStore.get_domain_key(entity)
  if separate_surfaces then
    return string.format("%d-%s", entity.surface.index, entity.force.name)
  end
  return entity.force.name
end

function DomainStore.get_domain_key_raw(surface_id, force_name)
  if separate_surfaces then
    return string.format("%d-%s", surface_id, force_name)
  end
  return force_name
end

--[[
Grab the table storage for a subdomain.

Example subdomain_key values: "storage", "priorities"
]]
function DomainStore.get_subdomain(domain_key, subdomain_key, default_fn)
  local domain = global.domains[domain_key]
  if domain == nil then
    domain = {}
    global.domains[domain_key] = domain
  end
  local subdomain = domain[subdomain_key]
  if subdomain == nil then
    subdomain = default_fn(domain_key)
    domain[subdomain_key] = subdomain
  end
  return subdomain
end

function DomainStore.initialise()
  if global.domains == nil then
    global.domains = {}
  end
end

return DomainStore
