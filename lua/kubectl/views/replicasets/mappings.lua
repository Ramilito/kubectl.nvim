local replicaset_view = require("kubectl.views.replicasets")
local state = require("kubectl.state")
local view = require("kubectl.views")
local err_msg = "Failed to extract ReplicaSet name or namespace."

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  },
}

function M.register() end

return M
