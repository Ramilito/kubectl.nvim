local deployments = require("kubectl.deployments")
local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

local M = {}

function M.Deployments()
	local results = commands.execute_shell_command("kubectl", { "get", "deployments", "-A", "-o=json" })
	local data = deployments.processRow(vim.json.decode(results))
	local pretty = tables.pretty_print(data, deployments.getHeaders())
	local hints = tables.generateHints({
		{ key = "<d>", desc = "desc" },
		{ key = "<enter>", desc = "pods" },
	})

	actions.new_buffer(pretty, "k8s_deployments", { is_float = false, hints = hints, title = "Deployments" })
end

function M.DeploymentDesc(deployment_desc, namespace)
	local desc =
		commands.execute_shell_command("kubectl", { "describe", "deployment", deployment_desc, "-n", namespace })
	actions.new_buffer(
		vim.split(desc, "\n"),
		"deployment_desc",
		{ is_float = true, title = deployment_desc, syntax = "yaml" }
	)
end

return M
