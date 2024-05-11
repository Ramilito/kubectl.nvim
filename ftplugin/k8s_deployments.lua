-- k8s_deployments.lua in ~/.config/nvim/ftplugin
local commands = require("kubectl.commands")
local actions = require("kubectl.actions")

vim.api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	desc = "kgp",
	callback = function()
		local results = commands.execute_shell_command("kubectl get pods -A")
		actions.new_buffer(results, "k8s_pods")
	end,
})
