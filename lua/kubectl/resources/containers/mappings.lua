local container_view = require("kubectl.resources.containers")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.resources.pods")
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
        pod_view.selectPod(pod_view.selection.pod, pod_view.selection.ns, container_name)
        pod_view.Logs()
      else
        print("Failed to extract logs.")
      end
    end,
  },
  ["<Plug>(kubectl.select_fullscreen)"] = {
    noremap = true,
    silent = true,
    desc = "Exec into",
    callback = function()
      local container_name = tables.getCurrentSelection(unpack({ 1 }))
      if container_name then
        container_view.selectContainer(container_name)
        vim.cmd("tabnew")
        vim.schedule(function()
          container_view.exec(pod_view.selection.pod, pod_view.selection.ns, true)
        end)
      else
        print("Failed to extract containers.")
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
  mappings.map_if_plug_not_set("n", "<cr>", "<Plug>(kubectl.select)")
  mappings.map_if_plug_not_set("n", "g<cr>", "<Plug>(kubectl.select_fullscreen)")
end

return M
