local nodes = require("kubectl.nodes")
local commands = require("kubectl.commands")
local tables = require("kubectl.view.tables")
local actions = require("kubectl.actions")

local M = {}

function M.Nodes()
  local results = commands.execute_shell_command("kubectl", { "get", "nodes", "-A", "-o=json" })
  local data = nodes.processRow(vim.json.decode(results))
  local pretty = tables.pretty_print(data, nodes.getHeaders())
  local hints = tables.generateHints({
    { key = "<d>", desc = "describe" },
  }, true, true)

  actions.buffer(pretty, "k8s_nodes", { hints = hints, title = "Nodes" })
end

function M.NodeDesc(node)
  local desc = commands.execute_shell_command("kubectl", { "describe", "node", node })
  actions.floating_buffer(vim.split(desc, "\n"), "k8s_node_desc", { title = node, syntax = "yaml" })
end

return M
