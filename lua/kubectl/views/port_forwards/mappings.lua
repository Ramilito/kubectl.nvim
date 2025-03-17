local mappings = require("kubectl.mappings")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.delete)"] = {
    noremap = true,
    silent = true,
    desc = "Delete port forward",
    callback = function()
      local id, resource = tables.getCurrentSelection(1, 2)
      vim.notify("Deleting port forward for resource " .. resource .. " with id: " .. id)

      local client = require("kubectl_client")
      client.portforward_stop(id)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
end

return M
