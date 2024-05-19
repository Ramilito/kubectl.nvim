local M = {}

-- Function to execute a shell command and return the output as a table of strings
function M.execute_shell_command(cmd)
	local handle = io.popen(cmd, "r")
	if handle == nil then
		return { "Failed to execute command: " .. cmd }
	end
	local result = handle:read("*a")
	handle:close()

	return result
end

return M
