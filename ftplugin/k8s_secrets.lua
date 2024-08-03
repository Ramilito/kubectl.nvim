local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local api = vim.api
local secrets_view = require("kubectl.views.secrets")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints({ { key = "<gd>", desc = "Describe selected secret" } })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gd", "", {
    noremap = true,
    silent = true,
    desc = "Describe resource",
    callback = function()
      local name, ns = secrets_view.getCurrentSelection()
      if ns and name then
        secrets_view.SecretDesc(ns, name)
      else
        api.nvim_err_writeln("Failed to describe pod name or namespace.")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(secrets_view.View)
  end
end

init()
