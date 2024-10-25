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
    { text = "grace period:", value = "-1", cmd = "--grace-period" },
    { text = "timeout:", value = "5s", cmd = "--timeout" },
    { text = "ignore daemonset:", enum = { "false", "true" }, cmd = "--ignore-daemonsets" },
    { text = "delete emptydir data:", enum = { "false", "true" }, cmd = "--delete-emptydir-data" },
    { text = "force:", enum = { "false", "true" }, cmd = "--force" },
    { text = "dry run:", enum = { "none", "client", "server" }, cmd = "--dry-run" },
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
