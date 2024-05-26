local event_view = require("kubectl.events.views")
local string_util = require("kubectl.utils.string")
local hl = require("kubectl.view.highlight")
local api = vim.api

local function getCurrentSelection()
	local line = api.nvim_get_current_line()
	local columns = vim.split(line, hl.symbols.tab)
	local message = string_util.trim(columns[6])
	return message
end

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	callback = function()
		local message = getCurrentSelection()
		if message then
			event_view.ShowMessage(message)
		else
			print("Failed to extract event message.")
		end
	end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
	noremap = true,
	silent = true,
	callback = function()
		event_view.Events()
	end,
})
