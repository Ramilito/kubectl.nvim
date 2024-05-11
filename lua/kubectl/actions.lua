local M = {}
local api = vim.api
local layout = require("kubectl.layout")

local function get_columns_to_hl(content, ft, word_column_number)
	local highlights_to_apply = {}
	local word_pattern = string.rep("%S+%s+", word_column_number - 1) .. "(%S+)"

	if ft == "k8s_pods" then
		for i, row in ipairs(content) do
			if i > 1 then
				local word_start, word_end, word = string.find(row, word_pattern)
				if word_start and word_end then
					table.insert(
						highlights_to_apply,
						{ line = i - 1, hl_group = "@comment.note", start = word_start - 1, stop = word_end }
					)
				end
			end
		end
	end
	return highlights_to_apply
end

local function get_lines_to_hl(content, ft)
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
				if start_pos and end_pos then
					table.insert(
						lines_to_highlight,
						{ line = i - 1, hl_group = highlight, start = start_pos - 1, stop = end_pos }
					)
				end
			end
		end
	end
	return lines_to_highlight
end

function M.new_buffer(content, filetype, title, is_float)
	local lines_to_highlight = get_lines_to_hl(content, filetype)
	local highlights_to_apply = get_columns_to_hl(content, filetype, 1)
	local buf = api.nvim_create_buf(false, true)

	api.nvim_buf_set_lines(buf, 0, -1, false, content)

	for _, line_info in ipairs(lines_to_highlight) do
		api.nvim_buf_add_highlight(buf, -1, line_info.hl_group, line_info.line, line_info.start, line_info.stop)
	end

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
