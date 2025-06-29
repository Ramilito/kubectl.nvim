local mappings = require("kubectl.mappings")
local service_view = require("kubectl.resources.services")
local err_msg = "Failed to extract service name or namespace."
local M = {}

M.overrides = {
  ["<Plug>(kubectl.portforward)"] = {
    noremap = true,
    silent = true,
    desc = "Port forward",
    callback = function()
      local name, ns = service_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end

      service_view.PortForward(name, ns)
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.portforward)")
end

return M
