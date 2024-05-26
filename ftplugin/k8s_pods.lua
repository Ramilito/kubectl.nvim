-- k8s_pods.lua in ~/.config/nvim/ftplugin
local hl = require("kubectl.view.highlight")
local api = vim.api
local view = require("kubectl.view")

local function getCurrentSelection()
	local line = api.nvim_get_current_line()
	local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
	return namespace, pod_name
end

api.nvim_buf_set_keymap(0, "n", "g?", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Hints({
			"      Hint: "
				.. hl.symbols.pending
				.. "l"
				.. hl.symbols.clear
				.. " logs | "
				.. hl.symbols.pending
				.. " d "
				.. hl.symbols.clear
				.. "desc | "
				.. hl.symbols.pending
				.. "<cr> "
				.. hl.symbols.clear
				.. "containers",
		})
	end,
})

api.nvim_buf_set_keymap(0, "n", "t", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.PodTop()
	end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
	noremap = true,
	silent = true,
	callback = function()
		local namespace, pod_name = getCurrentSelection()
		if pod_name and namespace then
			view.PodDesc(pod_name, namespace)
		else
			api.nvim_err_writeln("Failed to describe pod name or namespace.")
		end
	end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Deployments()
	end,
})

api.nvim_buf_set_keymap(0, "n", "l", "", {
	noremap = true,
	silent = true,
	callback = function()
		local namespace, pod_name = getCurrentSelection()
		if pod_name and namespace then
			view.PodLogs(pod_name, namespace)
		else
			print("Failed to extract pod name or namespace.")
		end
	end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	callback = function()
		local namespace, pod_name = getCurrentSelection()
		if pod_name and namespace then
			view.PodContainers(pod_name, namespace)
		else
			print("Failed to extract containers.")
		end
	end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Pods()
	end,
})

