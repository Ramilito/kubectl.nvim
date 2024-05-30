local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")

local M = {}
local selection = {}

function M.Pods()
  ResourceBuilder:new("pods", { "get", "pods", "-A", "-o=json" })
    :fetch()
    :decodeJson()
    :process(definition.processRow)
    :prettyPrint(definition.getHeaders)
    :addHints({
      { key = "<l>", desc = "logs" },
      { key = "<d>", desc = "describe" },
      { key = "<t>", desc = "top" },
      { key = "<enter>", desc = "containers" },
    }, true, true)
    :setFilter(FILTER)
    :display("k8s_pods")
end

function M.PodTop()
  ResourceBuilder:new("top", { "top", "pods", "-A" }):fetch():splitData():displayFloat("k8s_top", "Top", "")
end

function M.PodLogs(pod_name, namespace)
  ResourceBuilder:new("logs", { "logs", pod_name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_pod_logs", pod_name, "less")
end

function M.PodDesc(pod_name, namespace)
  ResourceBuilder:new("desc", { "describe", "pod", pod_name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_pod_desc", pod_name, "yaml")
end

function M.ExecContainer(container_name)
  commands.execute_terminal(
    "kubectl",
    { "exec", "-it", selection.pod, "-n", selection.ns, "-c ", container_name, "--", "/bin/sh" }
  )
end

function M.PodContainers(pod_name, namespace)
  selection = { pod = pod_name, ns = namespace }
  ResourceBuilder:new("containers", { "get", "pods", pod_name, "-n", namespace, "-o=json" })
    :fetch()
    :decodeJson()
    :process(definition.processContainerRow)
    :prettyPrint(definition.getContainerHeaders)
    :addHints({
      { key = "<enter>", desc = "exec" },
    }, false, false)
    :displayFloat("k8s_containers", pod_name, "", true)
end

return M
