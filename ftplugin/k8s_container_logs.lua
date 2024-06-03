local api = vim.api
local container_view = require("kubectl.views.containers")
local pod_view = require("kubectl.views.pods")

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    container_view.PodContainers()
  end,
})

vim.api.nvim_buf_set_keymap(0, "n", "f", "", {
  noremap = true,
  silent = true,
  desc = "Tail logs",
  callback = function()
    container_view.tailContainerLogs(pod_view.selection.pod, pod_view.selection.ns)
  end,
})
