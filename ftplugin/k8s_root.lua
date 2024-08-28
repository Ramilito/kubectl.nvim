local string_utils = require("kubectl.utils.string")
local api = vim.api

local function getCurrentSelection()
  local line = api.nvim_get_current_line()
  local selection = line:match("([a-zA-z]+)")
  return selection
end

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(select)", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local selection = getCurrentSelection()
      if selection then
        local view = require("kubectl.views." .. string.lower(string_utils.trim(selection)))
        pcall(view.View)
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
