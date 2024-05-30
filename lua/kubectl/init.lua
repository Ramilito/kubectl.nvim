local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local completion = require("kubectl.completion")
local pod_view = require("kubectl.views.pods")
local filter_view = require("kubectl.views.filter")
local view = require("kubectl.views")

local M = {}

KUBE_CONFIG = commands.execute_shell_command("kubectl", {
  "config",
  "view",
  "--minify",
  "-o",
  'jsonpath=\'{range .clusters[*]}{"Cluster: "}{.name}{end} \z
                {range .contexts[*]}{"\\nContext: "}{.context.cluster}{"\\nUsers:   "}{.context.user}{end}\'',
})
FILTER = ""

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
      callback = function()
        filter_view.filter()
      end,
    })
  end,
})

return M
