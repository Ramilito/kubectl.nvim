-- k8s_deployments.lua in ~/.config/nvim/ftplugin
local api = vim.api
local deplyoment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local string_util = require("kubectl.utils.string")
local view = require("kubectl.views")

local function getCurrentSelection()
	local line = api.nvim_get_current_line()
	local columns = vim.split(line, hl.symbols.tab)
	local namespace = string_util.trim(columns[1])
	local deployment_name = string_util.trim(columns[2])

	return namespace, deployment_name
end

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
		local namespace, deployment_name = getCurrentSelection()
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
