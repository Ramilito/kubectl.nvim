local M = {}
local defaults = {
	hints = true,
	context = true,
	float_size = {
		-- Almost fullscreen:
		-- width = 1.0,
		-- height = 0.95, -- Setting it to 1 will be cutoff by statuscolumn

		-- For more context aware size:
		width = 0.9,
		height = 0.8,
		col = 10,
		row = 5,
	},
}

M.options = {}

function M.setup(options)
	M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

M.setup()

return M
