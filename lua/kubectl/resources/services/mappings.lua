local mapping_helpers = require("kubectl.utils.mapping_helpers")
local mappings = require("kubectl.mappings")
local service_view = require("kubectl.resources.services")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.portforward)"] = {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = mapping_helpers.safe_callback(service_view, service_view.PortForward),
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.portforward)")
end

return M
