local pod_view = require("kubectl.views.pods")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "f", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      local container_view = require("kubectl.views.containers")
      vim.print(vim.inspect(container_view.selection))
      pod_view.TailLogs(pod_view.selection.pod, pod_view.selection.ns, container_view.selection)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "gw", "", {
    noremap = true,
    silent = true,
    desc = "Toggle wrap",
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Add divider",
    callback = function()
      local width_of_window = vim.api.nvim_win_get_width(0)
      local line_count = vim.api.nvim_buf_line_count(0)
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { string.rep("-", width_of_window) })
      vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
