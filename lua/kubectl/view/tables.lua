local hl = require("kubectl.view.highlight")
local config = require("kubectl.config")
local M = {}

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

function M.generateHints(hintConfigs)
	local hint = ""

	if config.options.hints then
		hint = hl.symbols.success .. "Hint: " .. hl.symbols.clear
		for _, hintConfig in ipairs(hintConfigs) do
			hint = hint .. hl.symbols.pending .. hintConfig.key .. hl.symbols.clear .. " " .. hintConfig.desc .. " | "
		end
		hint = hint .. hl.symbols.pending .. "<R> " .. hl.symbols.clear .. "reload | "
		hint = hint .. hl.symbols.pending .. "<g?> " .. hl.symbols.clear .. "help"
		hint = hint .. "\n\n"
	end

	if config.options.context then
		for _, value in ipairs(vim.split(KUBE_CONFIG, "\n")) do
			hint = hint .. value .. "\n"
		end
	end

	if config.options.context or config.options.hints then
		local win = vim.api.nvim_get_current_win()
		hint = hint .. string.rep("―", vim.api.nvim_win_get_width(win))
	end

  return vim.split(hint, "\n")
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
		tbl = tbl
			.. hl.symbols.header
			.. header
			.. hl.symbols.clear
			.. "  "
			.. string.rep(" ", widths[columns[i]] - #header + 1)
	end
	tbl = tbl .. "\n"

	-- Create table rows
	for _, row in ipairs(data) do
		for _, col in ipairs(columns) do
			if type(row[col]) == "table" then
				local value = tostring(row[col].value)
				tbl = tbl
					.. row[col].symbol
					.. value
					.. hl.symbols.clear
					.. "  "
					.. string.rep(" ", widths[col] - #value + 1)
			else
				local value = tostring(row[col])
				tbl = tbl .. value .. hl.symbols.tab .. "  " .. string.rep(" ", widths[col] - #value + 1)
			end
		end
		tbl = tbl .. "\n"
	end

	return vim.split(tbl, "\n")
end

return M
