local actions = require("kubectl.actions")
local commands = require("kubectl.commands")
local deployments = require("kubectl.deployments")
local find = require("kubectl.utils.find")
local tables = require("kubectl.view.tables")

local M = {}

function M.Deployments()
  local results = commands.execute_shell_command("kubectl", { "get", "deployments", "-A", "-o=json" })
  local data = deployments.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, deployments.getHeaders())
  local hints = tables.generateHints({
    { key = "<d>", desc = "desc" },
    { key = "<enter>", desc = "pods" },
  }, true, true)

  actions.new_buffer(
    find.filter_line(pretty, FILTER),
    "k8s_deployments",
    { is_float = false, hints = hints, title = "Deployments" }
  )
end

function M.DeploymentDesc(deployment_desc, namespace)
  local desc = commands.execute_shell_command("kubectl", { "describe", "deployment", deployment_desc, "-n", namespace })
  actions.new_buffer(
    vim.split(desc, "\n"),
    "deployment_desc",
    { is_float = true, title = deployment_desc, syntax = "yaml" }
  )
end

return M
