local api = vim.api
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local root_view = require("kubectl.views.root")
local top_def = require("kubectl.views.top.definition")
local top_view = require("kubectl.views.top")

mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.top_pods)")
mappings.map_if_plug_not_set("n", "gn", "<Plug>(kubectl.top_nodes)")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(top_pods)", "", {
    noremap = true,
    silent = true,
    desc = "Top pods",
    callback = function()
      top_view.View()
      top_def.res_type = "pods"
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(top_nodes)", "", {
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
