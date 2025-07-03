local ingresses_view = require("kubectl.resources.ingresses")
local mappings = require("kubectl.mappings")
local err_msg = "Failed to extract ingress name or namespace."

local M = {}

M.overrides = {
  ["<Plug>(kubectl.browse)"] = {
    noremap = true,
    silent = true,
    desc = "Open host in browser",
    callback = function()
      local name, ns = ingresses_view.getCurrentSelection()

      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      ingresses_view.OpenBrowser(name, ns)
    end,
  },
}
function M.register()
  mappings.map_if_plug_not_set("n", "gx", "<Plug>(kubectl.browse)")
end

return M
