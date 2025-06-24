local container_view = require("kubectl.views.containers")
local err_msg = "Failed to extract pod name or namespace."
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.logs)"] = {
    desc = "View logs",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      pod_view.selectPod(name, ns, nil)
      pod_view.Logs()
    end,
  },
  ["<Plug>(kubectl.select)"] = {
    desc = "Select",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      pod_view.selectPod(name, ns)
      container_view.View(pod_view.selection.pod, pod_view.selection.ns)
    end,
  },
  ["<Plug>(kubectl.portforward)"] = {
    desc = "Port forward",
    callback = function()
      local name, ns = pod_view.getCurrentSelection()
      if not ns or not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end

      pod_view.PortForward(name, ns)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gl", "<Plug>(kubectl.logs)")
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.portforward)")
  mappings.map_if_plug_not_set("n", "<cr>", "<Plug>(kubectl.select)")
end

return M
