--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
}

function client.set_implementation()
  local state = require("kubectl.state")
  client.implementation = require("kubectl.client.rust")
  client.implementation.init_runtime(state.context["current-context"])
end

function client.get_resource(...)
  return client.implementation.get_resource(...)
end

function client.get_store(resource_name)
  return client.implementation.get_store(resource_name)
end

function client.start_watcher(...)
  return client.implementation.start_watcher(...)
end

return client
