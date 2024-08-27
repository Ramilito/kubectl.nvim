local definition = require("kubectl.views.crds.definition")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local api = vim.api
local crds_view = require("kubectl.views.crds")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local km = config.options.keymaps
  local gl = km.global
  local c = km.crds
  api.nvim_buf_set_keymap(bufnr, "n", gl.help.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.help.key),
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", c.view.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(c.view),
    callback = function()
      local kind = crds_view.getCurrentSelection()
      local fallback_view = require("kubectl.views.fallback")
      fallback_view.View(nil, kind)
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
    loop.start_loop(crds_view.Draw)
  end
end

init()
