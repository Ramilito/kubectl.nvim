local pod_view = require("kubectl.views.pods")

--- Set key mappings for the buffer
local function set_keymaps()
  vim.api.nvim_buf_set_keymap(0, "n", "f", "", {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      pod_view.TailLogs()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps()
end

init()
