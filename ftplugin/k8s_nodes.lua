local api = vim.api
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local node_view = require("kubectl.views.nodes")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.drain)", "", {
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

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.uncordon)", "", {
    noremap = true,
    silent = true,
    desc = "UnCordon node",
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.UnCordon(node)
      else
        api.nvim_err_writeln("Failed to cordon node.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.cordon)", "", {
    noremap = true,
    silent = true,
    desc = "Cordon node",
    callback = function()
      local node = node_view.getCurrentSelection()
      if node then
        node_view.Cordon(node)
      else
        api.nvim_err_writeln("Failed to cordon node.")
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

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gR", "<Plug>(kubectl.drain)")
  mappings.map_if_plug_not_set("n", "gU", "<Plug>(kubectl.uncordon)")
  mappings.map_if_plug_not_set("n", "gC", "<Plug>(kubectl.cordon)")
end)
