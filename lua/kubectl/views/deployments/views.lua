local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local deployments = require("kubectl.views.deployments")
local find = require("kubectl.utils.find")
local tables = require("kubectl.utils.tables")

local M = {}

function M.Deployments()
  local results = commands.execute_shell_command("kubectl", { "get", "deployments", "-A", "-o=json" })
  local data = deployments.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, deployments.getHeaders())
  local hints = tables.generateHints({
    { key = "<d>", desc = "desc" },
    { key = "<enter>", desc = "pods" },
  }, true, true)

  actions.buffer(find.filter_line(pretty, FILTER), "k8s_deployments", { hints = hints, title = "Deployments" })
end

function M.DeploymentDesc(deployment_desc, namespace)
  local desc = commands.execute_shell_command("kubectl", { "describe", "deployment", deployment_desc, "-n", namespace })
  actions.floating_buffer(vim.split(desc, "\n"), "deployment_desc", { title = deployment_desc, syntax = "yaml" })
end

return M
