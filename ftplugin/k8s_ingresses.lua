local api = vim.api
local ingresses_view = require("kubectl.views.ingresses")
local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")

--- Set key mappings for the buffer
local function set_keymap(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      overview_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymap(0)
  if not loop.is_running() then
    loop.start_loop(ingresses_view.Draw)
  end
end

init()
