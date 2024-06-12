local filter_view = require("kubectl.views.filter")
local namespace_view = require("kubectl.views.namespace")
local state = require("kubectl.utils.state")

local M = {}

function M.register()
  vim.api.nvim_buf_set_keymap(0, "n", "<leader>k", "", {
    noremap = true,
    silent = true,
    desc = "Toggle",
    callback = function()
      vim.cmd("bdelete!")
    end,
  })
  vim.api.nvim_buf_set_keymap(0, "n", "<C-f>", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      filter_view.filter()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<C-n>", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      namespace_view.Namespace()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "s", "", {
    noremap = false,
    silent = true,
    desc = "Sort",
    callback = function()
      local current_word = vim.fn.expand("<cword>")
      state.setSortBy(current_word)
      vim.api.nvim_input("R")
    end,
  })
end
return M
