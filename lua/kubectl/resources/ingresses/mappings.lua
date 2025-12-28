local ingresses_view = require("kubectl.resources.ingresses")
local mapping_helpers = require("kubectl.utils.mapping_helpers")
local mappings = require("kubectl.mappings")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.browse)"] = {
    noremap = true,
    silent = true,
    desc = "Open host in browser",
    callback = mapping_helpers.safe_callback(ingresses_view, ingresses_view.OpenBrowser),
  },
}
function M.register()
  mappings.map_if_plug_not_set("n", "gx", "<Plug>(kubectl.browse)")
end

return M
