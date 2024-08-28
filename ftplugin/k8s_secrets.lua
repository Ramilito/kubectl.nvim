local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local api = vim.api
local secrets_view = require("kubectl.views.secrets")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(secrets_view.Draw)
  end
end

init()
