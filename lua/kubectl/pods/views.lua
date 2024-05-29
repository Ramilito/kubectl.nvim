local actions = require("kubectl.actions")
local commands = require("kubectl.commands")
local find = require("kubectl.utils.find")
local pods = require("kubectl.pods")
local tables = require("kubectl.view.tables")

local M = {}
local selection = {}

function M.Pods()
  local results = commands.execute_shell_command("kubectl", { "get", "pods", "-A", "-o=json" })
  local data = pods.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, pods.getHeaders())

  local hints = tables.generateHints({
    { key = "<l>", desc = "logs" },
    { key = "<d>", desc = "desc" },
    { key = "<t>", desc = "top" },
    { key = "<enter>", desc = "containers" },
  }, true, true)
  actions.buffer(find.filter_line(pretty, FILTER), "k8s_pods", { hints = hints })
end

function M.PodTop()
  local results = commands.execute_shell_command("kubectl", { "top", "pods", "-A" })
  actions.floating_buffer(vim.split(results, "\n"), "k8s_pods", { title = "Top" })
end

function M.PodLogs(pod_name, namespace)
  local results = commands.execute_shell_command("kubectl", { "logs", pod_name, "-n", namespace })
  actions.floating_buffer(vim.split(results, "\n"), "k8s_pod_logs", { title = pod_name, syntax = "less" })
end

function M.PodDesc(pod_name, namespace)
  local desc = commands.execute_shell_command("kubectl", { "describe", "pod", pod_name, "-n", namespace })
  actions.floating_buffer(vim.split(desc, "\n"), "k8s_pod_desc", { title = pod_name, syntax = "yaml" })
end

function M.ExecContainer(container_name)
  commands.execute_terminal(
    "kubectl",
    { "exec", "-it", selection.pod, "-n", selection.ns, "-c ", container_name, "--", "/bin/sh" }
  )
end

function M.PodContainers(pod_name, namespace)
  selection = { pod = pod_name, ns = namespace }
  local results = commands.execute_shell_command("kubectl", {
    "get",
    "pods",
    pod_name,
    "-n",
    namespace,
    "-o=json",
  })

  local data = pods.processContainerRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, pods.getContainerHeaders())
  actions.floating_buffer(pretty, "k8s_containers", { title = pod_name })
end
return M
