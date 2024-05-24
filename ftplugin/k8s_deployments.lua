-- k8s_deployments.lua in ~/.config/nvim/ftplugin
local view = require("kubectl.view")

local hl = require("kubectl.view.highlight")
local actions = require("kubectl.actions")

vim.api.nvim_buf_set_keymap(0, "n", "g?", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Hints({
			"      Hint: " .. hl.symbols.pending .. "d " .. "desc | " .. hl.symbols.pending .. "<cr> " .. "pods",
		})
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "d", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, deployment_name = line:match("^(%S+)%s+(%S+)")
		if deployment_name and namespace then
			view.DeploymentDesc(deployment_name, namespace)
		else
			vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
		end
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	desc = "kgp",
	callback = function()
		view.Pods()
	end,
})
