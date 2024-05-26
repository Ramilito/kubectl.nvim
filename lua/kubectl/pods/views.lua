local pods = require("kubectl.pods")
local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

local M = {}
function M.Pods()
	local results = commands.execute_shell_command("kubectl", { "get", "pods", "-A", "-o=json" })
	local data = pods.processRow(vim.json.decode(results))
	local pretty = tables.pretty_print(data, pods.getHeaders())
	local hints = tables.generateHints({
		{ key = "<l>", desc = "logs" },
		{ key = "<d>", desc = "desc" },
		{ key = "<t>", desc = "top" },
		{ key = "<enter>", desc = "containers" },
	})
	actions.new_buffer(pretty, "k8s_pods", { is_float = false, hints = hints })
end

function M.PodTop()
	local results = commands.execute_shell_command("kubectl", { "top", "pods", "-A" })
	actions.new_buffer(vim.split(results, "\n"), "k8s_pods", { is_float = true, title = "Top" })
end

function M.PodLogs(pod_name, namespace)
	local results = commands.execute_shell_command("kubectl", { "logs", pod_name, "-n", namespace })
	actions.new_buffer(vim.split(results, "\n"), "less", { is_float = true, title = pod_name })
end

function M.PodDesc(pod_name, namespace)
	local desc = commands.execute_shell_command("kubectl", { "describe", "pod", pod_name, "-n", namespace })
	actions.new_buffer(vim.split(desc, "\n"), "yaml", { is_float = true, title = pod_name })
end

function M.PodContainers(pod_name, namespace)
	local results = commands.execute_shell_command("kubectl", {
		"get",
		"pods",
		pod_name,
		"-n",
		namespace,
		"-o",
		'jsonpath=\'{range .status.containerStatuses[*]} \z
  {"name: "}{.name} \z
  {"\\n ready: "}{.ready} \z
  {"\\n state: "}{.state} \z
  {"\\n"}{end}\'',
	})
	actions.new_buffer(vim.split(results, "\n"), "yaml", { is_float = true, title = pod_name })
end
return M
