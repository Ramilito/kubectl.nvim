-- k8s_containers.lua in ~/.config/nvim/ftplugin
local api = vim.api
local hl = require("kubectl.actions.highlight")
local pod_view = require("kubectl.views.pods")
local string_util = require("kubectl.utils.string")
local view = require("kubectl.views")

local function getCurrentSelection()
	local line = api.nvim_get_current_line()
	local columns = vim.split(line, hl.symbols.tab)
	local container_name = string_util.trim(columns[1])

	return container_name
end

api.nvim_buf_set_keymap(0, "n", "g?", "", {
	noremap = true,
	silent = true,
	callback = function()
		view.Hints({
			"      Hint: "
				.. hl.symbols.pending
				.. "l"
				.. hl.symbols.clear
				.. " logs | "
				.. hl.symbols.pending
				.. " d "
				.. hl.symbols.clear
				.. "desc | "
				.. hl.symbols.pending
				.. "<cr> "
				.. hl.symbols.clear
				.. "containers",
		})
	end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	callback = function()
		local container_name = getCurrentSelection()
		if container_name then
			pod_view.ExecContainer(container_name)
		else
			print("Failed to extract containers.")
		end
	end,
})
