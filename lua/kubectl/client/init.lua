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
  commands.run_async("init_client_async", {}, function(ok)
    if ok then
      client.implementation.init_metrics()
    end
    callback(ok)
  end)
end

function client.shutdown_async()
  commands.run_async("shutdown_async", {}, function() end)
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

--- @class kubectl.LogConfig
--- @field pods table[] Array of {name, namespace} tables
--- @field container? string Target container name
--- @field timestamps? boolean Include timestamps in output
--- @field since? string Duration like "5m", "1h"
--- @field follow? boolean Stream continuously
--- @field previous? boolean Fetch from previous container instance
--- @field prefix? boolean Force prefix behavior

--- Create a log streaming session
--- @param config kubectl.LogConfig
--- @return kubectl.LogSession
function client.log_session(config)
  return client.implementation.log_session(config)
end

--- @class kubectl.DescribeConfig
--- @field name string Resource name
--- @field namespace? string Namespace
--- @field context string Kubernetes context
--- @field gvk table {k, g, v}

--- Create a describe streaming session
--- @param config kubectl.DescribeConfig
--- @return kubectl.DescribeSession
function client.describe_session(config)
  return client.implementation.describe_session(config)
end

--- @param view_name string
--- @return kubectl.DashboardSession
function client.start_buffer_dashboard(view_name)
  return client.implementation.start_buffer_dashboard(view_name)
end

function client.get_config()
  return client.implementation.get_config()
end

--- Get drift results comparing local manifests against cluster state.
--- @param path string Path to diff against the cluster
--- @param hide_unchanged? boolean Filter out unchanged resources
--- @return {entries: table[], counts: {changed: integer, unchanged: integer, errors: integer}, build_error: string|nil}
function client.get_drift(path, hide_unchanged)
  return client.implementation.get_drift(path, hide_unchanged)
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

function client.toggle_json(input)
  return client.implementation.toggle_json(input)
end

return client
