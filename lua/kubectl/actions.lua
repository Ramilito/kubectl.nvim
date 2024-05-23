local M = {}
local api = vim.api
local layout = require("kubectl.view.layout")

function M.set_winbar(content)
	vim.defer_fn(function()
		vim.api.nvim_set_option_value("winbar", content, { scope = "local" })
	end, 100)
end

function M.new_buffer(content, filetype, title, opts)
	local bufname = title

	if opts.is_float then
		bufname = "kubectl_float"
	end

	local buf = vim.fn.bufnr(bufname)

	if buf == -1 then
		buf = api.nvim_create_buf(false, true)
		api.nvim_buf_set_name(buf, bufname)
	end

	api.nvim_buf_set_lines(buf, 0, -1, false, content)

	if opts.is_float then
		layout.float_layout(buf, filetype, title or "")
	else
		api.nvim_set_current_buf(buf)
		layout.main_layout(buf, filetype, title or "")
	end
end

return M
