local string_utils = require("kubectl.utils.string")
local api = vim.api

local function getCurrentSelection()
  local line = api.nvim_get_current_line()
  local selection = line:match("^(%S+)")

  return selection
end

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Select",
    callback = function()
      local selection = getCurrentSelection()
      if selection then
        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_close(win, true)

        local ok, view = pcall(require, "kubectl.views." .. string.lower(string_utils.trim(selection)))
        if ok then
          pcall(view.View)
        else
          local fallback_view = require("kubectl.views.fallback")
          fallback_view.View(nil, selection)
        end
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
