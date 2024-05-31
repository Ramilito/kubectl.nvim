local pod_view = require("kubectl.views.pods")

vim.api.nvim_buf_set_keymap(0, "n", "f", "", {
  noremap = true,
  silent = true,
  desc = "Tail logs",
  callback = function()
    pod_view.TailLogs()
  end,
})
