local mappings = require("kubectl.mappings")
local pods_top_view = require("kubectl.views.top_pods")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.top_pods)"] = {
    noremap = true,
    silent = true,
    desc = "Top pods",
    callback = function()
      pods_top_view.View()
    end,
  },
  ["<Plug>(kubectl.top_nodes)"] = {
    noremap = true,
    silent = true,
    desc = "Top nodes",
    callback = function()
      local top_view = require("kubectl.views.top_nodes")
      top_view.View()
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.top_pods)")
  mappings.map_if_plug_not_set("n", "gn", "<Plug>(kubectl.top_nodes)")
end

return M
