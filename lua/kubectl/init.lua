local commands = require("kubectl.actions.commands")
local completion = require("kubectl.completion")
local config = require("kubectl.config")
local filter_view = require("kubectl.views.filter")
local namespace_view = require("kubectl.views.namespace")
local pod_view = require("kubectl.views.pods")
local view = require("kubectl.views")

local M = {}

KUBE_CONFIG = vim.json.decode(commands.execute_shell_command("kubectl", {
  "config",
  "view",
  "--minify",
  "-o",
  "json",
}))

NAMESPACE = KUBE_CONFIG.contexts[1].context.namespace
FILTER = ""
SORTBY = ""

function M.open()
  pod_view.Pods()
end

function M.setup(options)
  config.setup(options)
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
        namespace_view.pick()
      end,
    })

    vim.api.nvim_buf_set_keymap(0, "n", "s", "", {
      noremap = false,
      silent = true,
      desc = "Sort",
      callback = function()
        local current_word = vim.fn.expand("<cword>")
        SORTBY = current_word
        vim.api.nvim_input("R")
      end,
    })
  end,
})

return M
