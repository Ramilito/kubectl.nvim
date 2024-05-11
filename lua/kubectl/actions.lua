local M = {}
local api = vim.api
local layout = require("kubectl.layout")

local function processed_content(content, ft)
	local highlight_conditions = {
		Running = "@comment.note",
		Error = "@comment.error",
		Failed = "@comment.error",
		Succeeded = "@comment.note",
	}

	local lines_to_highlight = {}

	if ft == "k8s_pods" then
		for i, row in ipairs(content) do
			for condition, highlight in pairs(highlight_conditions) do
				local start_pos, end_pos = string.find(row, condition)
				print(start_pos, end_pos)
				if start_pos and end_pos then
					table.insert(
						lines_to_highlight,
						{ line = i - 1, hl_group = highlight, start = start_pos - 1, stop = end_pos }
					)
				end
			end
		end
	end
	return content, lines_to_highlight
end

function M.new_buffer(content, filetype, title, is_float)
	local processed, lines_to_highlight = processed_content(content, filetype)
	local buf = api.nvim_create_buf(false, true)

	api.nvim_buf_set_lines(buf, 0, -1, false, processed)

	for _, line_info in ipairs(lines_to_highlight) do
		api.nvim_buf_add_highlight(buf, -1, line_info.hl_group, line_info.line, line_info.start, line_info.stop)
	end

	if is_float then
		layout.float_layout(buf, filetype, title or "")
	else
		layout.main_layout(buf, filetype, title or "")
	end
end

function M.set_filetype(ft)
	api.nvim_buf_set_option(0, "filetype", ft)
end

return M
