local M = {}
local api = vim.api
local layout = require("kubectl.view.layout")
local commands = require("kubectl.commands")

function M.new_buffer(content, filetype, opts)
	local bufname = opts.title or ""

	if opts.is_float then
		bufname = "kubectl_float"
	end

	local buf = vim.fn.bufnr(bufname)

	if buf == -1 then
		buf = api.nvim_create_buf(false, true)
		api.nvim_buf_set_name(buf, bufname)
	end

	if opts.hints then
		api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
		api.nvim_buf_set_lines(buf, #opts.hints, -1, false, content)
	else
		api.nvim_buf_set_lines(buf, 0, -1, false, content)
	end

	if opts.is_float then
		layout.float_layout(buf, filetype, opts.title or "")
	else
		api.nvim_set_current_buf(buf)
		layout.main_layout(buf, filetype, opts.title or "")
	end
end

return M
