local pod_view = require("kubectl.views.pods")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local pl = config.options.keymaps.pods.logs
  vim.api.nvim_buf_set_keymap(bufnr, "n", pl.follow.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(pl.follow),
    callback = function()
      pod_view.TailLogs()
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", pl.wrap.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(pl.wrap),
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
