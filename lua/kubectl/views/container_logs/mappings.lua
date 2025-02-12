local container_view = require("kubectl.views.containers")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local str = require("kubectl.utils.string")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.previous_logs)"] = {
    noremap = true,
    silent = true,
    desc = "Previous logs",
    callback = function()
      if container_view.show_previous == "true" then
        container_view.show_previous = "false"
      else
        container_view.show_previous = "true"
      end
      container_view.logs(pod_view.selection.pod, pod_view.selection.ns, false)
    end,
  },
  ["<Plug>(kubectl.follow)"] = {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      pod_view.TailLogs(pod_view.selection.pod, pod_view.selection.ns, container_view.selection)
    end,
  },
  ["<Plug>(kubectl.wrap)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle wrap",
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
    end,
  },
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Add divider",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      str.divider(buf)
    end,
  },

  ["<Plug>(kubectl.history)"] = {
    noremap = true,
    silent = true,
    desc = "Log history",
    callback = function()
      vim.ui.input({ prompt = "Since (seconds)=", default = container_view.log_since }, function(input)
        container_view.log_since = input
        container_view.logs(pod_view.selection.pod, pod_view.selection.ns, false)
      end)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "f", "<Plug>(kubectl.follow)")
  mappings.map_if_plug_not_set("n", "gw", "<Plug>(kubectl.wrap)")
  mappings.map_if_plug_not_set("n", "gh", "<Plug>(kubectl.history)")
  mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
  mappings.map_if_plug_not_set("n", "gpp", "<Plug>(kubectl.previous_logs)")
end

return M
