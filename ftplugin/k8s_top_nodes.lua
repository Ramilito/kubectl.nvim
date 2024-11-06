local api = vim.api
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local nodes_top_view = require("kubectl.views.top-nodes")
local top_def = require("kubectl.views.top.definition")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.top_pods)", "", {
    noremap = true,
    silent = true,
    desc = "Top pods",
    callback = function()
      local top_view = require("kubectl.views.top-pods")
      top_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.top_nodes)", "", {
    noremap = true,
    silent = true,
    desc = "Top nodes",
    callback = function()
      nodes_top_view.View()
      top_def.res_type = "nodes"
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(nodes_top_view.View)
  end
end

init()

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.top_pods)")
  mappings.map_if_plug_not_set("n", "gn", "<Plug>(kubectl.top_nodes)")
end)
