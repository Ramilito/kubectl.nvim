local M = {}

M.definition = {
  resource = "columns",
  display = "Toggle Columns",
  ft = "k8s_columns",
  title = "Columns",
  hints = {
    { key = "<Plug>(kubectl.toggle_column)", desc = "toggle column" },
    { key = "<Plug>(kubectl.select)", desc = "close" },
  },
  panes = {
    { title = "Columns" },
  },
}

return M
