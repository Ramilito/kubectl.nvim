local M = {}
local api = vim.api

-- Function to calculate column widths
local function calculate_column_widths(rows, columns)
	local widths = {}
	for _, row in ipairs(rows) do
		for _, column in pairs(columns) do
			widths[column] = math.max(widths[column] or 0, #tostring(row[column]))
		end
	end

	return widths
end

-- Function to print the table
function M.pretty_print(data, headers)
	local tbl = ""

	local columns = {}
	for k, v in pairs(headers) do
		columns[k] = v:lower()
	end

	local widths = calculate_column_widths(data, columns)
	for key, value in pairs(widths) do
		widths[key] = math.max(#key, value)
	end

	-- Create table header
	for i, header in ipairs(headers) do
		tbl = tbl .. header .. string.rep(" ", widths[columns[i]] - #header + 1)
	end
	tbl = tbl .. "\n"

	-- Create table rows
	for _, row in pairs(data) do
		for _, col in ipairs(columns) do
			local value = tostring(row[col])
			tbl = tbl .. value .. string.rep(" ", widths[col] - #value + 1)
		end
		tbl = tbl .. "\n"
	end

	return vim.split(tbl, "\n")
end

return M
