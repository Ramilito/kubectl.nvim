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

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local selection = getCurrentSelection()
      if selection then
        if selection == "Deployments" then
          deployment_view.View()
        elseif selection == "Events" then
          event_view.View()
        elseif selection == "Nodes" then
          node_view.View()
        elseif selection == "Secrets" then
          secret_view.View()
        elseif selection == "Services" then
          service_view.View()
        elseif selection == "Configmaps" then
          configmaps_view.View()
        end
      else
        print("Failed to extract containers.")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
