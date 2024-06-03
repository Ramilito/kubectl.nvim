-- k8s_containers.lua in ~/.config/nvim/ftplugin
local api = vim.api
local pod_view = require("kubectl.views.pods")

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    pod_view.PodContainers()
  end,
})
