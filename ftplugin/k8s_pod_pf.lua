local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "gk", "", {
    noremap = true,
    silent = true,
    desc = "Kill port forward",
    callback = function()
      local pid = tables.getCurrentSelection(1)
      print(pid)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
