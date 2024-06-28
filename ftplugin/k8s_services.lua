local api = vim.api
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local service_view = require("kubectl.views.services")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({ { key = "<d>", desc = "Describe selected service" } })
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    service_view.Services()
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
      service_view.ServiceDesc(namespace, name)
    else
      api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

if not loop.is_running() then
  loop.start_loop(service_view.Services)
end
