local api = vim.api
local loop = require("kubectl.utils.loop")
local node_view = require("kubectl.views.nodes")
local root_view = require("kubectl.views.root")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints({
        { key = "<gd>", desc = "Describe selected node" },
        { key = "<gC>", desc = "Cordon selected node" },
        { key = "<gU>", desc = "UnCordon selected node" },
        { key = "<gR>", desc = "Drain selected node" },
      })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gR", "", {
    noremap = true,
    silent = true,
    desc = "Drain node",
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.Drain(node)
      else
        api.nvim_err_writeln("Failed to drain node.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gU", "", {
    noremap = true,
    silent = true,
    desc = "UnCordon node",
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.UnCordon(node)
      else
        api.nvim_err_writeln("Failed to cordone node.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gC", "", {
    noremap = true,
    silent = true,
    desc = "Cordon node",
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.Cordon(node)
      else
        api.nvim_err_writeln("Failed to cordone node.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gd", "", {
    noremap = true,
    silent = true,
    desc = "Describe resource",
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.Desc(node)
      else
        api.nvim_err_writeln("Failed to describe node.")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(node_view.View)
  end
end

init()
