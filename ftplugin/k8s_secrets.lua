local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local api = vim.api
local secrets_view = require("kubectl.views.secrets")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    local hints = ""
    hints = hints .. tables.generateHintLine("<d>", "Describe selected secret \n")
    hints = hints .. tables.generateHintLine("<R>", "Refresh view \n")
    hints = hints .. tables.generateHintLine("<bs>", "Go to root view \n")
    view.Hints(hints)
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    secrets_view.Secrets()
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
      secrets_view.SecretDesc(namespace, name)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

if not loop.is_running() then
  loop.start_loop(secrets_view.Secrets)
end
