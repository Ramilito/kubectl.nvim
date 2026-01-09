local M = {}

M.definition = {
  resource = "columns",
  display = "Toggle Columns",
  ft = "k8s_columns",
  title = "Columns",
  hints = {
    { key = "<Plug>(kubectl.tab)", desc = "toggle" },
    { key = "<Plug>(kubectl.move_up)", desc = "move up" },
    { key = "<Plug>(kubectl.move_down)", desc = "move down" },
    { key = "<Plug>(kubectl.reset_order)", desc = "reset order" },
    { key = "<Plug>(kubectl.quit)", desc = "close" },
  },
  panes = {
    { title = "Columns" },
  },
}

return M
