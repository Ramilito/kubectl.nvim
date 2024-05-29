local commands = require("kubectl.commands")
local config = require("kubectl.config")
local pod_view = require("kubectl.pods.views")
local deployment_view = require("kubectl.deployments.views")
local events_view = require("kubectl.events.views")
local nodes_view = require("kubectl.nodes.views")
local secrets_view = require("kubectl.secrets.views")
local services_view = require("kubectl.services.views")
local filter_view = require("kubectl.filter.view")
local view = require("kubectl.view")

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
    if vim.tbl_contains({ "pods", "pod", "po" }, opts.fargs[2]) then
      pod_view.Pods()
    elseif vim.tbl_contains({ "deployments", "deployment", "deploy" }, opts.fargs[2]) then
      deployment_view.Deployments()
    elseif vim.tbl_contains({ "events", "event", "ev" }, opts.fargs[2]) then
      events_view.Events()
    elseif vim.tbl_contains({ "nodes", "node", "no" }, opts.fargs[2]) then
      nodes_view.Nodes()
    elseif vim.tbl_contains({ "secrets", "secret", "sec" }, opts.fargs[2]) then
      secrets_view.Secrets()
    elseif vim.tbl_contains({ "services", "service", "svc" }, opts.fargs[2]) then
      services_view.Services()
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
