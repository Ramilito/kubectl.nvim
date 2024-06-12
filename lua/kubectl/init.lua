local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local mappings = require("kubectl.mappings")
local state = require("kubectl.utils.state")

local M = {}

function M.open()
  local pod_view = require("kubectl.views.pods")
  hl.setup()
  state.setup()
  pod_view.Pods()
end

function M.setup(options)
  local completion = require("kubectl.completion")
  config.setup(options)
  state.setNS(config.options.namespace)

  local group = vim.api.nvim_create_augroup("Kubectl", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "k8s_*",
    callback = function()
      mappings.register()
    end,
  })

  vim.api.nvim_create_user_command("Kubectl", function(opts)
    local view = require("kubectl.views")
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
end

return M
