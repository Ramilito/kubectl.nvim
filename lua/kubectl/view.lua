local commands = require("kubectl.commands")
local actions = require("kubectl.actions")
local tables = require("kubectl.tables")

local M = {}

local function processRow(rows, columns)
	local data = {}
	for _, row in pairs(rows.items) do
		local restartCount = 0
		local containers = 0
		local ready = 0
		for _, value in ipairs(row.status.containerStatuses) do
			containers = containers + 1
			if value.ready then
				ready = ready + 1
			end
			restartCount = restartCount + value.restartCount
		end

		local pod = {
			namespace = row.metadata.namespace,
			name = row.metadata.name,
			status = row.status.phase,
			restarts = restartCount,
			ready = ready .. "/" .. containers,
		}

		table.insert(data, pod)
	end
	return data
end

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
	local data = processRow(rows, headers)

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
