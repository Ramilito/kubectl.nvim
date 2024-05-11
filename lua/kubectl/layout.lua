local M = {}
local api = vim.api

local function set_buf_options(buf, win, filetype)
	vim.wo[win].winhighlight = "Normal:Normal"
	api.nvim_set_option_value("filetype", filetype, { buf = buf })
	api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
	api.nvim_set_option_value("cursorline", true, { win = win })
	-- vim.api.nvim_set_option_value("winbar", "hello world", { scope = "local" })
	-- api.nvim_set_option_value("winbar", "%* %t %*", { scope = "local" })
end

function M.main_layout(buf, filetype, title)
	local width = vim.o.columns
	local height = vim.o.lines
	local row = vim.o.lines
	local col = 10

	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "",
		width = math.floor(width),
		height = math.floor(height),
		row = row,
		border = "none",
		col = col,
		title = filetype .. " - " .. (title or ""),
	})

	set_buf_options(buf, win, filetype)
end

function M.float_layout(buf, filetype, title)
	local width = vim.o.columns - 10
	local height = 40
	local row = 0
	local col = 0

	local win = api.nvim_open_win(buf, true, {
		relative = "cursor",
		style = "minimal",
		width = math.floor(width),
		height = math.floor(height),
		row = row,
		border = "rounded",
		col = col,
		title = filetype .. " - " .. (title or ""),
	})

	set_buf_options(buf, win, filetype)
end

return M
