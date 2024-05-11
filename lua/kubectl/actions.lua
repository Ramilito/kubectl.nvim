local M = {}
local api = vim.api
local layout = require("kubectl.layout")

function M.new_buffer(content, filetype, title, is_float)
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buf, 0, -1, false, content)

	if is_float then
		layout.float_layout(buf, filetype, title and "")
	else
		layout.main_layout(buf, filetype, title and "")
	end
end

function M.set_filetype(ft)
	api.nvim_buf_set_option(0, "filetype", ft)
end

return M
