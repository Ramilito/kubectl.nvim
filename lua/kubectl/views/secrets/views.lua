local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local secrets = require("kubectl.views.secrets")
local tables = require("kubectl.utils.tables")

local M = {}

function M.Secrets()
  local results = commands.execute_shell_command("kubectl", { "get", "secrets", "-A", "-o=json" })
  local data = secrets.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, secrets.getHeaders())
  local hints = tables.generateHints({
    { key = "<d>", desc = "describe" },
  }, true, true)

  actions.buffer(find.filter_line(pretty, FILTER), "k8s_secrets", { hints = hints, title = "Secrets" })
end

function M.SecretDesc(namespace, name)
  local desc = commands.execute_shell_command("kubectl", { "describe", "secret", name, "-n", namespace })
  actions.floating_buffer(vim.split(desc, "\n"), "k8s_secret_desc", { title = name, syntax = "yaml" })
end

return M
