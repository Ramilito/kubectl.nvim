local state = require("kubectl.state")

--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
}

function client.set_implementation()
  client.implementation = require("kubectl_client")
  client.implementation.init_runtime(state.context["current-context"])
end

function client.get_resource(...)
  return client.implementation.get_resource(...)
end

function client.portforward_start(...)
  return client.implementation.portforward_start(...)
end

function client.portforward_list()
  return client.implementation.portforward_list()
end

function client.portforward_stop(id)
  return client.implementation.portforward_stop(id)
end

function client.pod_set_images(...)
  return client.implementation.pod_set_images(...)
end

function client.deployment_set_images(...)
  return client.implementation.deployment_set_images(...)
end

function client.get_config()
  return client.implementation.get_config()
end
function client.get_table(definition)
  local namespace = nil
  if state.ns and state.ns ~= "All" then
    namespace = state.ns
  end

  local sort_by = state.sortby[definition.resource].current_word
  local sort_order = state.sortby[definition.resource].order

  return client.implementation.get_table(definition.gvk.k, namespace, sort_by, sort_order, "")
end

function client.get_store(resource_name)
  local namespace = nil
  if state.ns and state.ns ~= "All" then
    namespace = state.ns
  end
  return client.implementation.get_store(resource_name, namespace)
end

return client
