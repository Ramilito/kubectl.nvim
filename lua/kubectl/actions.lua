local M = {}
local api = vim.api
local layout = require("kubectl.view.layout")
local hl = require("kubectl.view.highlight")

function M.new_buffer(content, filetype, title, opts)
	local bufname = "kubectl"

	if opts.is_float then
		bufname = "kubectl_float"
	end

	local buf = vim.fn.bufnr(bufname)

	if buf == -1 then
		buf = api.nvim_create_buf(false, false)
		api.nvim_buf_set_name(buf, bufname)
	end

	api.nvim_buf_set_lines(buf, 0, -1, false, content)

	if opts.is_float then
		layout.float_layout(buf, filetype, title or "")
	else
		layout.main_layout(buf, filetype, title or "")
	end
end

return M
