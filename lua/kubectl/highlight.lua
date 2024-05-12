local M = {}

--TODO: This doesn't handle if same row column has same value as target column
function M.get_columns_to_hl(content, column_indices)
	local highlights_to_apply = {}
	local column_delimiter = "%s+"

	for i, row in ipairs(content) do
		if i > 1 then -- Skip the first line since it's column names
			local columns = {}
			for column in row:gmatch("([^" .. column_delimiter .. "]+)") do
				table.insert(columns, column)
			end
			for _, col_index in ipairs(column_indices) do
				local column = columns[col_index]
				if column then
					local start_pos, end_pos = row:find(column, 1, true)
					if start_pos and end_pos then
						table.insert(highlights_to_apply, {
							line = i - 1,
							hl_group = "@comment.note",
							start = start_pos - 1,
							stop = end_pos,
						})
					end
				end
			end
		end
	end
	return highlights_to_apply
end

function M.get_lines_to_hl(content, conditions)
	local lines_to_highlight = {}
	for i, row in ipairs(content) do
		for condition, highlight in pairs(conditions) do
			local start_pos, end_pos = string.find(row, condition)
			if start_pos and end_pos then
				table.insert(
					lines_to_highlight,
					{ line = i - 1, hl_group = highlight, start = start_pos - 1, stop = end_pos }
				)
			end
		end
	end
	return lines_to_highlight
end

return M
