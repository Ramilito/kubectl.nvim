local commands = require("kubectl.commands")
local config = require("kubectl.config")
local actions = require("kubectl.actions")

local M = {}

function M.open()
	local results = commands.execute_shell_command("kubectl get pods -A")
	actions.new_buffer(results, false, "k8s_pods")
end

function M.setup(options)
	config.setup(options)
end

return M
