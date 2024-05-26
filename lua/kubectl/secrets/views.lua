local secrets = require("kubectl.secrets")
local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

local M = {}

function M.Secrets()
	local results = commands.execute_shell_command("kubectl", { "get", "secrets", "-A", "-o=json" })
	local data = secrets.processRow(vim.json.decode(results))
	local pretty = tables.pretty_print(data, secrets.getHeaders())
	local hints = tables.generateHints({
		{ key = "<d>", desc = "describe" },
	})

	actions.new_buffer(pretty, "k8s_secrets", { is_float = false, hints = hints, title = "Secrets" })
end

function M.SecretDesc(namespace, name)
	local desc = commands.execute_shell_command("kubectl", { "describe", "secret", name, "-n", namespace })
	actions.new_buffer(vim.split(desc, "\n"), "yaml", { is_float = true, title = name })
end

return M
