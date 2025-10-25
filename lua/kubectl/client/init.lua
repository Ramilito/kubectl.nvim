local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")

--- @class kubectl.Client
local client = {
  --- @type kubectl.ClientImplementation
  implementation = require("kubectl.client.rust"),
}

function client.set_implementation(callback)
  client.implementation = require("kubectl_client")
  client.implementation.init_logging(vim.fn.stdpath("log"))
  client.implementation.init_runtime(state.context["current-context"])
  commands.run_async("validate_kube_clients", {}, function(ok)
    if ok then
      client.implementation.init_metrics()
    end
    vim.schedule(function()
      callback(ok)
    end)
  end)
end

function client.get_resource(...)
  return client.implementation.get_resource(...)
end

function client.get_all(...)
  return client.implementation.get_all(...)
end

function client.get_single(...)
  return client.implementation.get_single(...)
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

function client.deployment_set_images(name, ns, image_spec)
  return client.implementation.deployment_set_images(name, ns, image_spec)
end

function client.statefulset_set_images(...)
  return client.implementation.statefulset_set_images(...)
end

function client.daemonset_set_images(...)
  return client.implementation.daemonset_set_images(...)
end

function client.create_job_from_cronjob(...)
  return client.implementation.create_job_from_cronjob(...)
end

function client.suspend_cronjob(...)
  return client.implementation.suspend_cronjob(...)
end

function client.uncordon_node(name)
  return client.implementation.uncordon_node(name)
end

function client.cordon_node(name)
  return client.implementation.cordon_node(name)
end

function client.debug(ns, pod, image, target)
  return client.implementation.debug(ns, pod, image, target)
end

function client.exec(ns, pod, container, cmd)
  return client.implementation.exec(ns, pod, container, cmd)
end

function client.start_dashboard(view_name)
  return client.implementation.start_dashboard(view_name)
end

function client.get_config()
  return client.implementation.get_config()
end

function client.setup_queue()
  return client.implementation.setup_queue()
end

function client.pop_queue()
  return client.implementation.pop_queue()
end

function client.emit(key, payload)
  return client.implementation.emit(key, payload)
end

return client
