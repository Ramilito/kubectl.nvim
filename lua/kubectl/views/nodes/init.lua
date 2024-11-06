local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.nodes.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.Drain(node)
  local builder = ResourceBuilder:new("kubectl_drain")
  local node_def = {
    ft = "k8s_node_drain",
    display = "Drain node: " .. node .. "?",
    resource = node,
    cmd = { "drain", "nodes/" .. node },
  }
  local data = {
    { text = "grace period:", value = "-1", cmd = "--grace-period", type = "option" },
    { text = "timeout:", value = "5s", cmd = "--timeout", type = "option" },
    {
      text = "ignore daemonset:",
      value = "false",
      cmd = "--ignore-daemonsets",
      type = "flag",
    },
    {
      text = "delete emptydir data:",
      value = "false",
      cmd = "--delete-emptydir-data",
      type = "flag",
    },
    { text = "force:", value = "false", cmd = "--force", type = "flag" },
    {
      text = "dry run:",
      value = "none",
      options = { "none", "server", "client" },
      cmd = "--dry-run",
      type = "option",
    },
  }

  builder:action_view(node_def, data, function(args)
    commands.shell_command_async("kubectl", args, function(response)
      vim.schedule(function()
        vim.notify(response)
      end)
    end)
  end)
end

function M.UnCordon(node)
  commands.shell_command_async("kubectl", { "uncordon", "nodes/" .. node })
end

function M.Cordon(node)
  commands.shell_command_async("kubectl", { "cordon", "nodes/" .. node })
end

function M.Desc(node, _, reload)
  ResourceBuilder:view_float({
    resource = "nodes_desc_" .. node,
    ft = "k8s_node_desc",
    url = { "describe", "node", node },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
