-- k8s_pods.lua in ~/.config/nvim/ftplugin
local view = require("kubectl.view")
local actions = require("kubectl.actions")

actions.set_winbar(
	"      Hint: "
		.. "%#KubectlNote#"
		.. " l "
		.. "%*"
		.. "logs |"
		.. "%#KubectlNote#"
		.. " d "
		.. "%*"
		.. "desc |"
		.. "%#KubectlNote#"
		.. " <cr> "
		.. "%*"
		.. "containers"
)

vim.api.nvim_buf_set_keymap(0, "n", "d", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
		if pod_name and namespace then
			view.PodDesc(pod_name, namespace)
		else
			vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
		end
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Deployments()
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "l", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
		if pod_name and namespace then
			view.PodLogs(pod_name, namespace)
		else
			print("Failed to extract pod name or namespace.")
		end
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
		if pod_name and namespace then
			view.PodContainers(pod_name, namespace)
		else
			print("Failed to extract containers.")
		end
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "R", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Pods()
	end,
})
