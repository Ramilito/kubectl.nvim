local api = vim.api
local helm_view = require("kubectl.views.helm")
local loop = require("kubectl.utils.loop")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      vim.print("Select")
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(helm_view.Draw)
  end
end

init()
