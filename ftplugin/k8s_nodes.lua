local api = vim.api
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local node_view = require("kubectl.views.nodes")
local state = require("kubectl.state")
local view = require("kubectl.views")
local err_msg = "Failed to extract node name."

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      state.setFilter("")
      view.set_url_and_open_view({
        src = "nodes",
        dest = "pods",
        new_query_params = { fieldSelector = "spec.nodeName=" .. name },
        name = name,
      })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.drain)", "", {
    noremap = true,
    silent = true,
    desc = "Drain node",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      node_view.Drain(name)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.uncordon)", "", {
    noremap = true,
    silent = true,
    desc = "UnCordon node",
    callback = function()
      local name = node_view.getCurrentSelection()
      if not name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      node_view.UnCordon(name)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.cordon)", "", {
    noremap = true,
    silent = true,
    desc = "Cordon node",
    callback = function()
      local name = node_view.getCurrentSelection()
      if name then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      node_view.Cordon(name)
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
