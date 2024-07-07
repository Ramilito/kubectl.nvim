local api = vim.api
local container_view = require("kubectl.views.containers")
local pod_view = require("kubectl.views.pods")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
    noremap = true,
    silent = true,
    callback = function()
      container_view.PodContainers()
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "f", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      container_view.tailLogs(pod_view.selection.pod, pod_view.selection.ns)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
