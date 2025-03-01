local container_view = require("kubectl.views.containers")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.debug)"] = {
    noremap = true,
    silent = true,
    desc = "Debug",
    callback = function()
      local container_name = tables.getCurrentSelection(unpack({ 1 }))
      if container_name then
        container_view.selectContainer(container_name)
        container_view.debug(pod_view.selection.pod, pod_view.selection.ns)
      else
        print("Failed to create debug container.")
      end
    end,
  },
  ["<Plug>(kubectl.logs)"] = {
    noremap = true,
    silent = true,
    desc = "View logs",
    callback = function()
      local container_name = tables.getCurrentSelection(unpack({ 1 }))
      if container_name then
        container_view.selectContainer(container_name)
        container_view.logs(pod_view.selection.pod, pod_view.selection.ns)
      else
        print("Failed to extract logs.")
      end
    end,
  },
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Exec into",
    callback = function()
      local container_name = tables.getCurrentSelection(unpack({ 1 }))
      if container_name then
        container_view.selectContainer(container_name)
        container_view.exec(pod_view.selection.pod, pod_view.selection.ns)
      else
        print("Failed to extract containers.")
      end
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gl", "<Plug>(kubectl.logs)")
  mappings.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.debug)")
end

return M
