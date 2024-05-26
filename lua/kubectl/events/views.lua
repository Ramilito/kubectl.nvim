local events = require("kubectl.events")
local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

local M = {}

function M.Events()
	local results = commands.execute_shell_command("kubectl", { "get", "events", "-A", "-o=json" })
	local data = events.processRow(vim.json.decode(results))
	local pretty = tables.pretty_print(data, events.getHeaders())
	local hints = tables.generateHints({
		{ key = "<enter>", desc = "message" },
	})

	actions.new_buffer(pretty, "k8s_events", { is_float = false, hints = hints, title = "Events" })
end

function M.ShowMessage(event)
	local msg = event
	actions.new_buffer(vim.split(msg, "\n"), "less", { is_float = true, title = "Message" })
end

return M
