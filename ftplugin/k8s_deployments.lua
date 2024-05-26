-- k8s_deployments.lua in ~/.config/nvim/ftplugin
local root_view = require("kubectl.root.views")
local deplyoment_view = require("kubectl.deployments.views")
local pod_view = require("kubectl.pods.views")
local view = require("kubectl.view")
local hl = require("kubectl.view.highlight")
local api = vim.api

api.nvim_buf_set_keymap(0, "n", "g?", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Hints({
			"      Hint: "
				.. hl.symbols.pending
				.. "d "
				.. hl.symbols.clear
				.. "desc | "
				.. hl.symbols.pending
				.. "<cr> "
				.. hl.symbols.clear
				.. "pods",
		})
	end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, deployment_name = line:match("^(%S+)%s+(%S+)")
		if deployment_name and namespace then
			deplyoment_view.DeploymentDesc(deployment_name, namespace)
		else
			vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
		end
	end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	desc = "kgp",
	callback = function()
		pod_view.Pods()
	end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
	noremap = true,
	silent = true,
	callback = function()
		root_view.Root()
	end,
})
