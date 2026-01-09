local M = {}

M.definition = {
  resource = "columns",
  display = "Toggle Columns",
  ft = "k8s_columns",
  title = "Columns",
  hints = {
    { key = "<Plug>(kubectl.tab)", desc = "toggle" },
    { key = "<Plug>(kubectl.quit)", desc = "close" },
  },
  panes = {
    { title = "Columns" },
  },
}

return M
