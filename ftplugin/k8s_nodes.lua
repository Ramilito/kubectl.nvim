local node_view = require("kubectl.views.nodes")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local api = vim.api

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    node_view.Nodes()
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
    local node = tables.getCurrentSelection(unpack({ 1 }))
    if node then
      node_view.NodeDesc(node)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})
