local hl = require("kubectl.view.highlight")
local deployment_view = require("kubectl.deployments.views")
local view = require("kubectl.view")
local api = vim.api

local function getCurrentSelection()
	local line = api.nvim_get_current_line()
	local selection = line:match("^(%S+)")
	return selection
end

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	callback = function()
		local selection = getCurrentSelection()
		print(selection)
		if selection then

			-- pod_view.PodContainers(pod_name, namespace)
		else
			print("Failed to extract containers.")
		end
	end,
})
