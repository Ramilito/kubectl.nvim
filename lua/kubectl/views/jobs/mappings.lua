local job_view = require("kubectl.views.jobs")
local state = require("kubectl.state")
local view = require("kubectl.views")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = job_view.getCurrentSelection()
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  },
}

return M
