local mappings = require("kubectl.mappings")
local node_view = require("kubectl.views.nodes")
local state = require("kubectl.state")
local view = require("kubectl.views")
local err_msg = "Failed to extract node name."

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      state.setFilter("")
      view.set_url_and_open_view({
        src = "nodes",
        dest = "pods",
        new_query_params = { fieldSelector = "spec.nodeName=" .. name },
        name = name,
      })
    end,
  },
  ["<Plug>(kubectl.drain)"] = {
    noremap = true,
    silent = true,
    desc = "Drain node",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      node_view.Drain(name)
    end,
  },
  ["<Plug>(kubectl.uncordon)"] = {
    noremap = true,
    silent = true,
    desc = "UnCordon node",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      node_view.UnCordon(name)
    end,
  },
  ["<Plug>(kubectl.cordon)"] = {
    noremap = true,
    silent = true,
    desc = "Cordon node",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      node_view.Cordon(name)
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gR", "<Plug>(kubectl.drain)")
  mappings.map_if_plug_not_set("n", "gU", "<Plug>(kubectl.uncordon)")
  mappings.map_if_plug_not_set("n", "gC", "<Plug>(kubectl.cordon)")
end

return M
