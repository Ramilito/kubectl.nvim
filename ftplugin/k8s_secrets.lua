local secret_view = require("kubectl.views.secrets")
local string_util = require("kubectl.utils.string")
local root_view = require("kubectl.views.root")
local hl = require("kubectl.actions.highlight")
local api = vim.api

local function getCurrentSelection()
	local line = api.nvim_get_current_line()
	local columns = vim.split(line, hl.symbols.tab)
	local namespace = string_util.trim(columns[1])
	local name = string_util.trim(columns[2])
	return namespace, name
end

api.nvim_buf_set_keymap(0, "n", "R", "", {
	noremap = true,
	silent = true,
	callback = function()
		secret_view.Secrets()
	end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
	noremap = true,
	silent = true,
	callback = function()
		root_view.Root()
	end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
	noremap = true,
	silent = true,
	callback = function()
		local namespace, name = getCurrentSelection()
		if namespace and name then
			secret_view.SecretDesc(namespace, name)
		else
			api.nvim_err_writeln("Failed to describe pod name or namespace.")
		end
	end,
})
