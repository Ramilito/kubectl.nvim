-- k8s_pods.lua in ~/.config/nvim/ftplugin
local actions = require("kubectl.actions")
local commands = require("kubectl.commands")

local function show_pod_containers(pod_name, namespace)
	local cmd = "kubectl get pods "
		.. pod_name
		.. " -n "
		.. namespace
		.. ' -o jsonpath=\'{range .status.containerStatuses[*]} \z
  {"\tname: "}{.name} \z
  {"\\n\tready: "}{.ready} \z
  {"\\n\tstate: "}{.state} \z
  {"\\n"}{end}\''
	local results = commands.execute_shell_command(cmd)
	actions.new_buffer(results, "k8s_pod_containers", pod_name, true)
end

local function show_pod_logs(pod_name, namespace)
	local cmd = "kubectl logs " .. pod_name .. " -n " .. namespace
	local results = commands.execute_shell_command(cmd)
	actions.new_buffer(results, "k8s_logs", pod_name, true)
end

local function show_pod_desc(pod_name, namespace)
	local cmd = string.format("kubectl describe pod %s -n %s", pod_name, namespace)
	local desc = commands.execute_shell_command(cmd)
	actions.new_buffer(desc, "k8s_pod_desc", pod_name, true)
end

vim.api.nvim_buf_set_keymap(0, "n", "d", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
		if pod_name and namespace then
			show_pod_desc(pod_name, namespace)
		else
			vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
		end
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
	noremap = true,
	silent = true,
	callback = function()
		local results = commands.execute_shell_command("kubectl get deployments -A")
		actions.new_buffer(results, "k8s_deployments")
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "l", "", {
	noremap = true,
	silent = true,
	callback = function()
		local line = vim.api.nvim_get_current_line()
		local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
		if pod_name and namespace then
			show_pod_logs(pod_name, namespace)
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
			show_pod_containers(pod_name, namespace)
		else
			print("Failed to extract containers.")
		end
	end,
})

vim.api.nvim_buf_set_keymap(0, "n", "R", "", {
	noremap = true,
	silent = true,
	callback = function()
		local results = commands.execute_shell_command("kubectl get pods -A")
		actions.new_buffer(results, "k8s_pods")
	end,
})
