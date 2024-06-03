local api = vim.api
local namespace_view = require("kubectl.views.namespace")
local tables = require("kubectl.utils.tables")

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  callback = function()
    local name = tables.getCurrentSelection(unpack({ 1 }))
    if name then
      namespace_view.changeNamespace(name)
    else
      print("Failed to get namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    namespace_view.Namespace()
  end,
})
