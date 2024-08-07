local state = require("kubectl.state")

local M = {}

-- All main views
---@alias ViewTable table<string, string[]>
---@type ViewTable
M.views = {
  pods = { "pods", "pod", "po" },
  deployments = { "deployments", "deployment", "deploy" },
  events = { "events", "event", "ev" },
  nodes = { "nodes", "node", "no" },
  secrets = { "secrets", "secret", "sec" },
  services = { "services", "service", "svc" },
  configmaps = { "configmaps", "configmap", "configmaps" },
}

--- Open the kubectl view
function M.open()
  local pod_view = require("kubectl.views.pods")
  local hl = require("kubectl.actions.highlight")
  local kube = require("kubectl.actions.kube")

  hl.setup()
  kube.startProxy(function()
    state.setup(M.views)
    pod_view.View()
  end)
end

--- Setup kubectl with options
--- @param options KubectlOptions The configuration options for kubectl
function M.setup(options)
  local completion = require("kubectl.completion")
  local mappings = require("kubectl.mappings")
  local config = require("kubectl.config")
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
      if #opts.fargs == 2 then
        local ok, x_view = pcall(require, "kubectl.views." .. opts.fargs[2])
        if ok then
          pcall(x_view.View)
        else
          view = require("kubectl.views.fallback")
          view.View(nil, opts.fargs[2])
        end
      else
        view.UserCmd(opts.fargs)
      end
    elseif opts.fargs[1] == "diff" then
      completion.diff(opts.fargs[2])
    elseif opts.fargs[1] == "apply" then
      completion.apply()
    else
      view.UserCmd(opts.fargs)
    end
  end, {
    nargs = "*",
    complete = completion.user_command_completion,
  })

  vim.api.nvim_create_user_command("Kubectx", function(opts)
    completion.change_context(opts.fargs[1])
  end, {
    nargs = "*",
    complete = completion.list_contexts,
  })
end

return M
