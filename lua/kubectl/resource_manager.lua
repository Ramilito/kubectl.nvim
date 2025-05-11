-- FILE: builder_manager.lua
local ResourceBuilder = require("kubectl.resource_factory") -- Adjust the path
local manager = {}

-- We store them by resource name for easy retrieval
manager.builders = {}

--- Get or create a builder for the given resource
---@param resource string
---@return table builder
function manager.get_or_create(resource)
  if manager.builders[resource] then
    return manager.builders[resource]
  end
  local b = ResourceBuilder.new(resource)
  manager.builders[resource] = b
  return b
end

--- Get an existing builder (no creation)
---@param resource string
---@return table|nil builder
function manager.get(resource)
  return manager.builders[resource]
end

--- Remove a builder from the manager
---@param resource string
function manager.remove(resource)
  manager.builders[resource] = nil
end

return manager
