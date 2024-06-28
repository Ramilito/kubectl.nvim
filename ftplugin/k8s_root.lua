local configmaps_view = require("kubectl.views.configmaps")
local deployment_view = require("kubectl.views.deployments")
local event_view = require("kubectl.views.events")
local node_view = require("kubectl.views.nodes")
local secret_view = require("kubectl.views.secrets")
local service_view = require("kubectl.views.services")
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
      elseif selection == "Configmaps" then
        configmaps_view.Configmaps()
      end
    else
      print("Failed to extract containers.")
    end
  end,
})
