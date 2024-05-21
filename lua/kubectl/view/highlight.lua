local M = {}
local api = vim.api

vim.api.nvim_set_hl(0, "KubectlHeader", { fg = "#569CD6" }) -- Blue
vim.api.nvim_set_hl(0, "KubectlWarning", { fg = "#D19A66" }) -- Orange
vim.api.nvim_set_hl(0, "KubectlError", { fg = "#D16969" }) -- Red
vim.api.nvim_set_hl(0, "KubectlInfo", { fg = "#608B4E" }) -- Green
vim.api.nvim_set_hl(0, "KubectlDebug", { fg = "#DCDCAA" }) -- Yellow
vim.api.nvim_set_hl(0, "KubectlSuccess", { fg = "#4EC9B0" }) -- Cyan
vim.api.nvim_set_hl(0, "KubectlPending", { fg = "#C586C0" }) -- Purple
vim.api.nvim_set_hl(0, "KubectlDeprecated", { fg = "#D4A5A5" }) -- Pink
vim.api.nvim_set_hl(0, "KubectlExperimental", { fg = "#CE9178" }) -- Brown
vim.api.nvim_set_hl(0, "KubectlNote", { fg = "#9CDCFE" }) -- Light Blue

-- Define M.symbols for tags
M.symbols = {
	header = "◆",
	warning = "⚠",
	error = "✖",
	info = "ℹ",
	debug = "⚑",
	success = "✓",
	pending = "☐",
	deprecated = "☠",
	experimental = "⚙",
	note = "✎",
}

local tag_patterns = {
	{ pattern = M.symbols.header .. "\\w\\+", group = "KubectlHeader" }, -- Headers
	{ pattern = M.symbols.warning .. "\\w\\+", group = "KubectlWarning" }, -- Warnings
	{ pattern = M.symbols.error .. "\\w\\+", group = "KubectlError" }, -- Errors
	{ pattern = M.symbols.info .. "\\w\\+", group = "KubectlInfo" }, -- Info
	{ pattern = M.symbols.debug .. "\\w\\+", group = "KubectlDebug" }, -- Debug
	{ pattern = M.symbols.success .. "\\w\\+", group = "KubectlSuccess" }, -- Success
	{ pattern = M.symbols.pending .. "\\w\\+", group = "KubectlPending" }, -- Pending
	{ pattern = M.symbols.deprecated .. "\\w\\+", group = "KubectlDeprecated" }, -- Deprecated
	{ pattern = M.symbols.experimental .. "\\w\\+", group = "KubectlExperimental" }, -- Experimental
	{ pattern = M.symbols.note .. "\\w\\+", group = "KubectlNote" }, -- Note
}

function M.set_highlighting()
	for _, symbol in pairs(M.symbols) do
		vim.cmd("syntax match Conceal" .. ' "' .. symbol .. '" conceal')
	end

	for _, tag in ipairs(tag_patterns) do
		vim.fn.matchadd(tag.group, tag.pattern, 100, -1, { conceal = "" })
	end
	api.nvim_buf_set_option(0, "conceallevel", 2)
	api.nvim_buf_set_option(0, "concealcursor", "nc")
end

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
