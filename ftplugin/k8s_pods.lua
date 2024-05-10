-- k8s_pods.lua in ~/.config/nvim/ftplugin
vim.api.nvim_buf_create_user_command(0, "DescribePod", function()
	local line = vim.api.nvim_get_current_line()
	local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
	if pod_name and namespace then
		local cmd = string.format("kubectl describe pod %s -n %s", pod_name, namespace)
		local output = vim.fn.system(cmd)
		vim.api.nvim_out_write(output)
	else
		vim.api.nvim_err_writeln("Failed to extract pod name or namespace.")
	end
end, { desc = "Describe the selected pod" })
