local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")
local pods = require("kubectl.pods")

local M = {}

function M.Pods()
	local highlight_conditions = {
		Running = "@comment.note",
		Error = "@comment.error",
		Failed = "@comment.error",
		Succeeded = "@comment.note",
	}

	local results = commands.execute_shell_command("kubectl get pods -A -o=json")
	local headers = {
		"NAMESPACE",
		"NAME",
		"READY",
		"STATUS",
		"RESTARTS",
	}

	local rows = vim.json.decode(results)
	local data = pods.processRow(rows, headers)

	local pretty = tables.pretty_print(data, headers)
	actions.new_buffer(
		pretty,
		"k8s_pods",
		"pods",
		{ is_float = false, columns = { 2 }, conditions = highlight_conditions }
	)
end

function M.Deployments()
	local results = commands.execute_shell_command("kubectl get deployments -A")
	actions.new_buffer(results, "k8s_deployments", "Deployments", { columns = { 2 } })
end

function M.PodLogs(pod_name, namespace)
	local cmd = "kubectl logs " .. pod_name .. " -n " .. namespace
	local results = commands.execute_shell_command(cmd)
	actions.new_buffer(results, "k8s_logs", pod_name, { is_float = true })
end

function M.PodDesc(pod_name, namespace)
	local cmd = string.format("kubectl describe pod %s -n %s", pod_name, namespace)
	local desc = commands.execute_shell_command(cmd)
	actions.new_buffer(desc, "k8s_pod_desc", pod_name, { is_float = true })
end

function M.PodContainers(pod_name, namespace)
	local cmd = "kubectl get pods "
		.. pod_name
		.. " -n "
		.. namespace
		.. ' -o jsonpath=\'{range .status.containerStatuses[*]} \z
  {"name: "}{.name} \z
  {"\\n ready: "}{.ready} \z
  {"\\n state: "}{.state} \z
  {"\\n"}{end}\''
	local results = commands.execute_shell_command(cmd)
	actions.new_buffer(results, "k8s_pod_containers", pod_name, { is_float = true })
end

return M
