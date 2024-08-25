local container_view = require("kubectl.views.containers")
local pod_view = require("kubectl.views.pods")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "f", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      container_view.tailLogs(pod_view.selection.pod, pod_view.selection.ns)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "w", "", {
    noremap = true,
    silent = true,
    desc = "Wrap logs",
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
      -- toggle wrap
      -- vim.api.nvim_command("set wrap!")
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
