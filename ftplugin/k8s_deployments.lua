-- k8s_pods.lua in ~/.config/nvim/ftplugin
local commands = require("kubectl.commands")
local actions = require("kubectl.actions")

local init = function()
	local results = commands.execute_shell_command("kubectl get deployments -A")
	actions.show_results_buffer(results, false)
end

init()
