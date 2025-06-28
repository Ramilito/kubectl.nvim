local api_resources_view = require("kubectl.resources.api-resources")
local overview_view = require("kubectl.views.overview")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.go_up)"] = {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      overview_view.View()
    end,
  },
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local name = api_resources_view.getCurrentSelection()
      if not name then
        vim.notify("Failed to extract API resource name.", vim.log.levels.ERROR)
        return
      end
      local view = require("kubectl.views")
      view.view_or_fallback(name)
    end,
  },
}

M.register = function() end

return M
