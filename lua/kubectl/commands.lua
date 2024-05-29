local M = {
	top_level_commands = {
		"annotate",
		"api-resources",
		"api-versions",
		"apply",
		"attach",
		"auth",
		"autoscale",
		"certificate",
		"cluster-info",
		"completion",
		"config",
		"cordon",
		"cp",
		"create",
		"debug",
		"delete",
		"describe",
		"diff",
		"drain",
		"edit",
		"events",
		"exec",
		"explain",
		"expose",
		"get",
		"help",
		"kustomize",
		"label",
		"logs",
		"options",
		"patch",
		"port-forward",
		"proxy",
		"replace",
		"rollout",
		"run",
		"scale",
		"set",
		"taint",
		"top",
		"uncordon",
		"version",
		"wait",
	},
}

function M.user_command_completion(_, cmd)
	local parts = {}
	for part in string.gmatch(cmd, "%S+") do
		table.insert(parts, part)
	end
	if #parts == 1 then
		return M.top_level_commands
	end
end

-- Function to execute a shell command and return the output as a table of strings
function M.execute_shell_command(cmd, args)
	local full_command = cmd .. " " .. table.concat(args, " ")
	local handle = io.popen(full_command, "r")
	if handle == nil then
		return { "Failed to execute command: " .. cmd }
	end
	local result = handle:read("*a")
	handle:close()

	return result
end

function M.execute_terminal(cmd, args)
	local full_command = cmd .. " " .. table.concat(args, " ")
	vim.fn.termopen(full_command, {
		on_exit = function(_, code, _)
			if code == 0 then
				print("Command executed successfully")
			else
				print("Command failed with exit code " .. code)
			end
		end,
	})
end

return M
