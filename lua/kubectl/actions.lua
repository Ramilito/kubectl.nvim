local M = {}
local api = vim.api
local layout = require("kubectl.layout")

function M.new_buffer(filetype, is_float)
	local buf = api.nvim_create_buf(false, true)
	local width = vim.o.columns
	local height = vim.o.lines

	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = height,
		col = 10,
	})

	api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "filetype", filetype)
	api.nvim_win_set_option(win, "cursorline", true)
end

-- Function to open a new buffer and display rows of results
function M.show_results_buffer(results, is_logs, filetype)
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

function M.set_filetype(ft)
	api.nvim_buf_set_option(0, "filetype", ft)
end

return M
