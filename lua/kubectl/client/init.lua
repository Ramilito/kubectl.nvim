local state = require("kubectl.state")

--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
}

function client.set_implementation()
  client.implementation = require("kubectl_client")
  client.implementation.init_runtime(state.context["current-context"])
  client.implementation.init_logging(vim.fn.stdpath("log"))
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

function client.daemonset_set_images(...)
  return client.implementation.daemonset_set_images(...)
end

function client.create_job_from_cronjob(...)
  return client.implementation.create_job_from_cronjob(...)
end

function client.get_config()
  return client.implementation.get_config()
end

return client
