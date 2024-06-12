local api = vim.api
local container_view = require("kubectl.views.containers")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

local col_indices = { 1, 2 }
api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    local hints = ""
    hints = hints .. tables.generateHintLine("<l>", "Shows logs for all containers in pod \n")
    hints = hints .. tables.generateHintLine("<d>", "Describe selected pod \n")
    hints = hints .. tables.generateHintLine("<t>", "Show resources used \n")
    hints = hints .. tables.generateHintLine("<enter>", "Opens container view \n")
    view.Hints(hints)
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
      api.nvim_err_writeln("Failed to extract pod name or namespace.")
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
      container_view.containers(pod_view.selection.pod, pod_view.selection.ns)
    else
      api.nvim_err_writeln("Failed to select pod.")
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

if not loop.is_running() then
  loop.start_loop(pod_view.Pods)
end
