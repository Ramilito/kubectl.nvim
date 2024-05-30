local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local pod_view = require("kubectl.views.pods")
local deployment_view = require("kubectl.views.deployments")
local events_view = require("kubectl.views.events")
local nodes_view = require("kubectl.views.nodes.views")
local secrets_view = require("kubectl.views.secrets.views")
local services_view = require("kubectl.views.services.views")
local filter_view = require("kubectl.views.filter.view")
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

local views = {
  pods = { "pods", "pod", "po", pod_view.Pods },
  deployments = { "deployments", "deployment", "deploy", deployment_view.Deployments },
  events = { "events", "event", "ev", events_view.Events },
  nodes = { "nodes", "node", "no", nodes_view.Nodes },
  secrets = { "secrets", "secret", "sec", secrets_view.Secrets },
  services = { "services", "service", "svc", services_view.Services },
}

local function find_view_command(arg)
  for _, v in pairs(views) do
    if vim.tbl_contains(v, arg) then
      return v[#v]
    end
  end
  return nil
end

vim.api.nvim_create_user_command("Kubectl", function(opts)
  if opts.fargs[1] == "get" then
    local cmd = find_view_command(opts.fargs[2])
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
  complete = commands.user_command_completion,
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
