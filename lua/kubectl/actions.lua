local M = {}
local api = vim.api
local layout = require("kubectl.layout")

function M.new_buffer(content, is_float, filetype, title)
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buf, 0, -1, false, content)
	local width = vim.o.columns
	local height = vim.o.lines
	local row = vim.o.lines
	local col = 10

	if is_float then
		width = vim.o.columns - 10
		height = 40
		row = 0
		col = 0
	end

	local win = api.nvim_open_win(buf, true, {
		relative = is_float and "cursor" or "editor",
		style = is_float and "minimal" or "",
		width = math.floor(width),
		height = math.floor(height),
		row = row,
		border = is_float and "rounded" or "none",
		col = col,
		title = filetype .. " - " .. (title or ""),
	})

	vim.wo[win].winhighlight = "Normal:Normal"
	api.nvim_set_option_value("filetype", filetype, { buf = buf })
	api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
	api.nvim_set_option_value("cursorline", true, { win = win })
end

function M.set_filetype(ft)
	api.nvim_buf_set_option(0, "filetype", ft)
end

return M
