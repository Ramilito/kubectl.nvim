local pods = require("kubectl.pods")
local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

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
	actions.new_buffer(pretty, "k8s_pods", { is_float = false, hints = hints })
end

function M.PodTop()
	local results = commands.execute_shell_command("kubectl", { "top", "pods", "-A" })
	actions.new_buffer(vim.split(results, "\n"), "k8s_pods", { is_float = true, title = "Top" })
end

function M.PodLogs(pod_name, namespace)
	local results = commands.execute_shell_command("kubectl", { "logs", pod_name, "-n", namespace })
	actions.new_buffer(vim.split(results, "\n"), "k8s_pod_logs", { is_float = true, title = pod_name, syntax = "less" })
end

function M.PodDesc(pod_name, namespace)
	local desc = commands.execute_shell_command("kubectl", { "describe", "pod", pod_name, "-n", namespace })
	actions.new_buffer(vim.split(desc, "\n"), "k8s_pod_desc", { is_float = true, title = pod_name, syntax = "yaml" })
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
	actions.new_buffer(pretty, "k8s_containers", { is_float = true, title = pod_name })
end
return M
