local definition = require("kubectl.views.pvc.definition")
local loop = require("kubectl.utils.loop")
local pvc_view = require("kubectl.views.pvc")
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

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Go to PVs",
    callback = function()
      local name, ns = pvc_view.getCurrentSelection()
      view.set_and_open_pv_of_pvc(name, ns)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(pvc_view.Draw)
  end
end

init()
