local loop = require("kubectl.utils.loop")
local sa_view = require("kubectl.views.sa")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints({
        { key = "<gd>", desc = "Describe selected serviceaccount" },
      })
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(sa_view.View)
  end
end

init()
