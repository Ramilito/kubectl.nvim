local M = {}
local defaults = {
	icons = true,
	diagnostics = true,
	buf_modified = true,
	filetype_exclude = {
		"help",
		"startify",
		"dashboard",
		"packer",
		"neo-tree",
		"neogitstatus",
		"NvimTree",
		"Trouble",
		"alpha",
		"lir",
		"Outline",
		"spectre_panel",
		"toggleterm",
		"TelescopePrompt",
		"prompt",
	},
}

M.options = {}

function M.setup(options)
	M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

M.setup()
return M
