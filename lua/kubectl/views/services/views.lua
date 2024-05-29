local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local services = require("kubectl.views.services")
local tables = require("kubectl.utils.tables")

local M = {}

function M.Services()
  local results = commands.execute_shell_command("kubectl", { "get", "services", "-A", "-o=json" })
  local data = services.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, services.getHeaders())
  local hints = tables.generateHints({
    { key = "<d>", desc = "describe" },
  }, true, true)

  actions.buffer(find.filter_line(pretty, FILTER), "k8s_services", { hints = hints, title = "Services" })
end

function M.ServiceDesc(namespace, name)
  local desc = commands.execute_shell_command("kubectl", { "describe", "svc", name, "-n", namespace })
  actions.floating_buffer(vim.split(desc, "\n"), "k8s_svc_desc", { title = name, syntax = "yaml" })
end

return M
