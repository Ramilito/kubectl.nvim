local M = {}

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

return M
