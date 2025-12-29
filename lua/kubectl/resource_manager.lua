local ResourceBuilder = require("kubectl.resource_factory")
local manager = {}

-- Storage for all managed instances (builders, sessions, etc.)
manager.instances = {}

--- Get or create an instance for the given key
---@param key any String or number key
---@param factory? fun(key: any): any Optional factory (defaults to ResourceBuilder.new)
---@return any instance
function manager.get_or_create(key, factory)
  if manager.instances[key] then
    return manager.instances[key]
  end
  local instance
  if factory then
    instance = factory(key)
  else
    instance = ResourceBuilder.new(key)
  end
  manager.instances[key] = instance
  return instance
end

--- Get an existing instance (no creation)
---@param key any
---@return any|nil
function manager.get(key)
  return manager.instances[key]
end

--- Remove an instance
---@param key any
function manager.remove(key)
  manager.instances[key] = nil
end

--- Iterate all instances matching a prefix
---@param prefix string
---@param fn fun(key: any, instance: any)
function manager.foreach(prefix, fn)
  for key, instance in pairs(manager.instances) do
    if type(key) == "string" and key:find("^" .. prefix) then
      fn(key, instance)
    end
  end
end

return manager
