local completion = require("kubectl.completion")
local config = require("kubectl.config")
local filter_view = require("kubectl.views.filter")
local hl = require("kubectl.actions.highlight")
local namespace_view = require("kubectl.views.namespace")
local pod_view = require("kubectl.views.pods")
local state = require("kubectl.utils.state")
local view = require("kubectl.views")

local M = {}

function M.open()
  local check = false
  hl.setup()
  check = state.setup()
  if check then
    pod_view.Pods()
  end
end

function M.setup(options)
  config.setup(options)
  NAMESPACE = config.options.namespace
end

vim.api.nvim_create_user_command("Kubectl", function(opts)
  if opts.fargs[1] == "get" then
    local cmd = completion.find_view_command(opts.fargs[2])
    if cmd then
      cmd()
    else
      view.UserCmd(opts.fargs)
    end
  else
    view.UserCmd(opts.fargs)
  end
end, {
  nargs = "*",
  complete = completion.user_command_completion,
})

local group = vim.api.nvim_create_augroup("Kubectl", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "k8s_*",
  callback = function()
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
  end,
})

return M
