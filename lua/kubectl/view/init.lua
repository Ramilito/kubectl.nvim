local actions = require("kubectl.actions")
local commands = require("kubectl.commands")

local M = {}

function M.Hints(hint)
	actions.new_buffer(hint, "k8s_hints", { is_float = true, title = "Hints" })
end

function M.UserCmd(args)
	local results = commands.execute_shell_command("kubectl", args )
	actions.new_buffer(vim.split(results, "\n"), "k8s_usercmd", { is_float = false, title = "UserCmd" })
end

return M
