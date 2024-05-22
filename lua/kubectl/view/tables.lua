local hl = require("kubectl.view.highlight")
local M = {}
local api = vim.api

-- Function to calculate column widths
local function calculate_column_widths(rows, columns)
	local widths = {}
	for _, row in ipairs(rows) do
		for _, column in pairs(columns) do
			if type(row[column]) == "table" then
				widths[column] = math.max(widths[column] or 0, #tostring(row[column].value))
			else
				widths[column] = math.max(widths[column] or 0, #tostring(row[column]))
			end
		end
	end

	return widths
end

-- Function to print the table
function M.pretty_print(data, headers)
	local columns = {}
	for k, v in ipairs(headers) do
		columns[k] = v:lower()
	end

	local widths = calculate_column_widths(data, columns)
	for key, value in pairs(widths) do
		widths[key] = math.max(#key, value)
	end

	local tbl = ""

	-- Create table header
	for i, header in pairs(headers) do
		tbl = tbl .. hl.symbols.header .. header .. "  " .. string.rep(" ", widths[columns[i]] - #header + 1)
	end
	tbl = tbl .. "\n"

	-- Create table rows
	for _, row in ipairs(data) do
		for _, col in ipairs(columns) do
			if type(row[col]) == "table" then
				local value = tostring(row[col].value)
				tbl = tbl .. row[col].symbol .. value .. "  " .. string.rep(" ", widths[col] - #value + 1)
			else
				local value = tostring(row[col])
				tbl = tbl .. value .. "  " .. string.rep(" ", widths[col] - #value + 1)
			end
		end
		tbl = tbl .. "\n"
	end

	return vim.split(tbl, "\n")
end

return M
