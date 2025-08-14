local mappings = require("kubectl.mappings")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views.portforward")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.delete)"] = {
    noremap = true,
    silent = true,
    desc = "Delete port forward",
    callback = function()
      local id, resource = tables.getCurrentSelection(1, 2)
      vim.notify("Deleting port forward for resource " .. resource .. " with id: " .. id)

      local client = require("kubectl.client")
      client.portforward_stop(id)
      vim.schedule(function()
        local line_number = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, {})
      end)
    end,
  },
  ["<Plug>(kubectl.browse)"] = {
    noremap = true,
    silent = true,
    desc = "Open host in browser",
    callback = function()
      local ok, host, ports = pcall(view.getCurrentSelection)
      if not ok then
        vim.notify("Failed to retrieve current selection: " .. tostring(host), vim.log.levels.ERROR)
        return
      end

      if not (host and host ~= "HOST") or not (ports and ports ~= "PORT") then
        vim.notify("Failed to retrieve host or port", vim.log.levels.ERROR)
        return
      end
      local port = vim.split(ports, ":")[1]
      if port then
        view.OpenBrowser(host, port)
      end
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
  mappings.map_if_plug_not_set("n", "gx", "<Plug>(kubectl.browse)")
end

return M
