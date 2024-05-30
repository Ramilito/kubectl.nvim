local root_view = require("kubectl.views.root")
local secret_view = require("kubectl.views.secrets")
local tables = require("kubectl.utils.tables")
local api = vim.api

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    secret_view.Secrets()
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  callback = function()
    root_view.Root()
  end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  callback = function()
    local namespace, name = tables.getCurrentSelection(unpack({ 1, 2 }))
    if namespace and name then
      secret_view.SecretDesc(namespace, name)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})
