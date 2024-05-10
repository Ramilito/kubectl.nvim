local commands = require("kubectl.commands")
local config = require("kubectl.config")

local M = {}
local api = vim.api

-- Function to open a new buffer and display rows of results
local function open_results_buffer(results, is_logs, filetype)
	-- Create a new buffer
	local buf = api.nvim_create_buf(false, true)

	-- Set buffer content to the results (each result as a separate line)
	api.nvim_buf_set_lines(buf, 0, -1, false, results)

	local width = vim.o.columns
	local height
	if is_logs then
		height = math.floor(vim.o.lines / 3) -- integer division to get one-third of the screen
	else
		height = vim.o.lines
	end
	print(height)
	local row = is_logs and vim.o.lines - height - 1 or 5

	-- Create a new window to display the buffer
	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = 10,
	})

	-- Set some options for the buffer
	api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	api.nvim_win_set_option(win, "cursorline", true)

	-- Set filetype for the buffer
	if filetype then
		api.nvim_buf_set_option(buf, "filetype", filetype)
	end
	return buf
end

-- Function to fetch and display pod logs
local function show_pod_logs(pod_name, namespace)
	local cmd = "kubectl logs " .. pod_name .. " -n " .. namespace
	local logs = commands.execute_shell_command(cmd)
	open_results_buffer(logs, true) -- Pass true to indicate this is a logs buffer
end

function M.open()
	local results = commands.execute_shell_command("kubectl get pods -A")

	local buf = open_results_buffer(results, false, "k8s_pods")
	-- Map <Enter> to print the current line
	api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		noremap = true,
		silent = true,
		callback = function()
			local line = api.nvim_get_current_line()
			local namespace, pod_name = line:match("^(%S+)%s+(%S+)")
			if pod_name and namespace then
				show_pod_logs(pod_name, namespace)
			else
				print("Failed to extract pod name or namespace.")
			end
		end,
	})
end

function M.setup(options)
	print("setup")
end

return M
