local hl = require("kubectl.view.highlight")
local deployment_view = require("kubectl.deployments.views")
local event_view = require("kubectl.events.views")
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
			if selection == "Deployments" then
				deployment_view.Deployments()
			elseif selection == "Events" then
				event_view.Events()
			end
			-- pod_view.PodContainers(pod_name, namespace)
		else
			print("Failed to extract containers.")
		end
	end,
})
