local clusterrolebinding_view = require("kubectl.views.clusterrolebinding")
local definition = require("kubectl.views.clusterrolebinding.definition")
local loop = require("kubectl.utils.loop")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local gl = require("kubectl.config").options.keymaps.global
  vim.api.nvim_buf_set_keymap(bufnr, "n", gl.help, "", {
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
    loop.start_loop(clusterrolebinding_view.Draw)
  end
end

init()
