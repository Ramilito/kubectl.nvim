local mapping_helpers = require("kubectl.utils.mapping_helpers")
local mappings = require("kubectl.mappings")
local node_view = require("kubectl.resources.nodes")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.drain)"] = {
    noremap = true,
    silent = true,
    desc = "Drain node",
    callback = mapping_helpers.safe_callback(node_view, node_view.Drain, true),
  },
  ["<Plug>(kubectl.uncordon)"] = {
    noremap = true,
    silent = true,
    desc = "UnCordon node",
    callback = mapping_helpers.safe_callback(node_view, node_view.UnCordon, true),
  },
  ["<Plug>(kubectl.cordon)"] = {
    noremap = true,
    silent = true,
    desc = "Cordon node",
    callback = mapping_helpers.safe_callback(node_view, node_view.Cordon, true),
  },
  ["<Plug>(kubectl.shell)"] = {
    noremap = true,
    silent = true,
    desc = "Shell into node",
    callback = mapping_helpers.safe_callback(node_view, node_view.Shell, true),
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gR", "<Plug>(kubectl.drain)")
  mappings.map_if_plug_not_set("n", "gU", "<Plug>(kubectl.uncordon)")
  mappings.map_if_plug_not_set("n", "gO", "<Plug>(kubectl.cordon)")
  mappings.map_if_plug_not_set("n", "gS", "<Plug>(kubectl.shell)")
end

return M
