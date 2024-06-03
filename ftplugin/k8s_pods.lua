local api = vim.api
local container_view = require("kubectl.views.containers")
local deployment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

local col_indices = { 1, 2 }
api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: "
        .. hl.symbols.pending
        .. "l"
        .. hl.symbols.clear
        .. " logs | "
        .. hl.symbols.pending
        .. " d "
        .. hl.symbols.clear
        .. "desc | "
        .. hl.symbols.pending
        .. "<cr> "
        .. hl.symbols.clear
        .. "containers",
    })
  end,
})

api.nvim_buf_set_keymap(0, "n", "t", "", {
  noremap = true,
  silent = true,
  callback = function()
    pod_view.PodTop()
  end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      pod_view.PodDesc(pod_name, namespace)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  callback = function()
    deployment_view.Deployments()
  end,
})

api.nvim_buf_set_keymap(0, "n", "l", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      pod_view.selectPod(pod_name, namespace)
      pod_view.PodLogs()
    else
      print("Failed to extract pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, pod_name = tables.getCurrentSelection(unpack(col_indices))
    if pod_name and namespace then
      pod_view.selectPod(pod_name, namespace)
      container_view.podContainers(pod_view.selection.pod, pod_view.selection.ns)
    else
      print("Failed to extract containers.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    pod_view.Pods()
  end,
})
