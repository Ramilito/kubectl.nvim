local view = require("kubectl.view")
local config = require("kubectl.config")
local commands = require("kubectl.commands")

local M = {}

CONTEXT = commands.execute_shell_command("kubectl", { "config", "current-context" })
CLUSTER_NAME =
	commands.execute_shell_command("kubectl", { "config", "view", "--minify", "-o jsonpath='{.clusters[].name}'" })
function M.open()
	view.Pods()
end

function M.setup(options)
	config.setup(options)
end

return M
