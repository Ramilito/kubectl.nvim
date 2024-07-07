local api = vim.api
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local service_view = require("kubectl.views.services")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymap(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    callback = function()
      view.Hints({ { key = "<d>", desc = "Describe selected service" } })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
    noremap = true,
    silent = true,
    callback = function()
      service_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "d", "", {
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
end

--- Initialize the module
local function init()
  set_keymap(0)
  if not loop.is_running() then
    loop.start_loop(service_view.View)
  end
end

init()
