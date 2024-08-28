local api = vim.api
local definition = require("kubectl.views.top.definition")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local top_def = require("kubectl.views.top.definition")
local top_view = require("kubectl.views.top")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints(definition.hints)
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

  api.nvim_buf_set_keymap(bufnr, "n", "gp", "", {
    noremap = true,
    silent = true,
    desc = "Top pods",
    callback = function()
      top_view.View()
      top_def.res_type = "pods"
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gn", "", {
    noremap = true,
    silent = true,
    desc = "Top nodes",
    callback = function()
      top_view.View()
      top_def.res_type = "nodes"
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(top_view.View)
  end
end

init()
