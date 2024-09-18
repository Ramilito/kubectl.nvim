local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")
local api = vim.api
local configmaps_view = require("kubectl.views.configmaps")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
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
  set_keymaps(0)

  if not loop.is_running() then
    loop.start_loop(configmaps_view.Draw)
  end
end

init()
