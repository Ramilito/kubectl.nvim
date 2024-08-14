local definition = require("kubectl.views.pv.definition")
local loop = require("kubectl.utils.loop")
local pv_view = require("kubectl.views.pv")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints(definition.hints)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(pv_view.View)
  end
end

init()
