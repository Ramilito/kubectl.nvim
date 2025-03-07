local state = require("kubectl.state")

--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
}

function client.set_implementation()
  client.implementation = require("kubectl.client.rust")
  client.implementation.init_runtime(state.context["current-context"])
end

function client.open_resource_editor(...)
  return client.implementation.open_resource_editor(...)
end

function client.get_resource(...)
  return client.implementation.get_resource(...)
end

function client.get_table(definition)
  local namespace = nil
  if state.ns and state.ns ~= "All" then
    namespace = state.ns
  end

  local sort_by = state.sortby[definition.resource].current_word
  local sort_order = state.sortby[definition.resource].order

  return client.implementation.get_table(definition.resource_name, namespace, sort_by, sort_order)
end

function client.get_store(resource_name)
  local namespace = nil
  if state.ns and state.ns ~= "All" then
    namespace = state.ns
  end
  return client.implementation.get_store(resource_name, namespace)
end

function client.start_watcher(...)
  return client.implementation.start_watcher(...)
end

return client
