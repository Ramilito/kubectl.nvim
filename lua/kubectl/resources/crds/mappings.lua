local crds_view = require("kubectl.resources.crds")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Open resource view",
    callback = function()
      local kind = crds_view.getCurrentSelection()
      local view = require("kubectl.views")
      view.resource_or_fallback(kind)
    end,
  },
}

M.register = function() end

return M
