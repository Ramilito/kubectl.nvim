local base64 = require("kubectl.utils.base64")
local api = vim.api

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<cr>", "", {
    noremap = true,
    silent = true,
    desc = "Base64Decode",
    callback = function()
      local line = vim.api.nvim_get_current_line()

      local code = line:match(":%s*(.+)")
      if code then
        local decoded = base64.base64decode(code)
        vim.notify(decoded)
      else
        vim.notify("No base64encoded text found")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
