local deployment_view = require("kubectl.deployments.views")
local event_view = require("kubectl.events.views")
local node_view = require("kubectl.nodes.views")
local service_view = require("kubectl.services.views")
local secret_view = require("kubectl.secrets.views")
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
		if selection then
			if selection == "Deployments" then
				deployment_view.Deployments()
			elseif selection == "Events" then
				event_view.Events()
			elseif selection == "Nodes" then
				node_view.Nodes()
			elseif selection == "Secrets" then
				secret_view.Secrets()
			elseif selection == "Services" then
				service_view.Services()
			end
		else
			print("Failed to extract containers.")
		end
	end,
})
