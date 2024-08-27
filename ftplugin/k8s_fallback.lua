local definition = require("kubectl.views.fallback.definition")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local api = vim.api
local fallback_view = require("kubectl.views.fallback")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local gl = config.options.keymaps.global
  api.nvim_buf_set_keymap(bufnr, "n", gl.help.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.help),
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", gl.go_up.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.go_up),
    callback = function()
      root_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(fallback_view.Draw)
  end
end

init()
