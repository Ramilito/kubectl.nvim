local M = {}
local api = vim.api
local layout = require("kubectl.layout")
local hl = require("kubectl.highlight")

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

	local lines_to_highlight = opts.conditions and hl.get_lines_to_hl(content, opts.conditions)
	local highlights_to_apply = opts.columns and hl.get_columns_to_hl(content, opts.columns)

	api.nvim_buf_set_lines(buf, 0, -1, false, content)

	if lines_to_highlight then
		for _, line_info in ipairs(lines_to_highlight) do
			api.nvim_buf_add_highlight(buf, -1, line_info.hl_group, line_info.line, line_info.start, line_info.stop)
		end
	end

	if highlights_to_apply then
		for _, highlight_info in ipairs(highlights_to_apply) do
			api.nvim_buf_add_highlight(
				buf,
				-1,
				highlight_info.hl_group,
				highlight_info.line,
				highlight_info.start,
				highlight_info.stop
			)
		end
	end

	if opts.is_float then
		layout.float_layout(buf, filetype, title or "")
	else
		layout.main_layout(buf, filetype, title or "")
	end
end

function M.set_filetype(ft)
	api.nvim_buf_set_option(0, "filetype", ft)
end

return M
