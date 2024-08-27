local api = vim.api
local definition = require("kubectl.views.nodes.definition")
local loop = require("kubectl.utils.loop")
local node_view = require("kubectl.views.nodes")
local root_view = require("kubectl.views.root")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local gl = config.options.keymaps.global
  local n = config.options.keymaps.nodes
  api.nvim_buf_set_keymap(bufnr, "n", gl.help.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.help),
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", gl.go_up.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.go_up),
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", n.drain.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(n.drain),
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.Drain(node)
      else
        api.nvim_err_writeln("Failed to drain node.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", n.uncordon.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(n.uncordon),
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.UnCordon(node)
      else
        api.nvim_err_writeln("Failed to cordone node.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", n.cordon.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(n.cordon),
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.Cordon(node)
      else
        api.nvim_err_writeln("Failed to cordone node.")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(node_view.Draw)
  end
end

init()
