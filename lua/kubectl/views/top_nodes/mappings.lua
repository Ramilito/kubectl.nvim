local mappings = require("kubectl.mappings")
local nodes_top_view = require("kubectl.views.top_nodes")
local top_def = require("kubectl.views.top.definition")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.top_pods)"] = {
    noremap = true,
    silent = true,
    desc = "Top pods",
    callback = function()
      local top_view = require("kubectl.views.top_pods")
      top_view.View()
    end,
  },

  ["<Plug>(kubectl.top_nodes)"] = {
    noremap = true,
    silent = true,
    desc = "Top nodes",
    callback = function()
      nodes_top_view.View()
      top_def.res_type = "nodes"
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.top_pods)")
  mappings.map_if_plug_not_set("n", "gn", "<Plug>(kubectl.top_nodes)")
end

return M
