local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.nodes.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "nodes"
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "node" },
    informer = { enabled = true },
    hints = {
      { key = "<Plug>(kubectl.cordon)", desc = "cordon", long_desc = "Cordon selected node" },
      { key = "<Plug>(kubectl.uncordon)", desc = "uncordon", long_desc = "UnCordon selected node" },
      { key = "<Plug>(kubectl.drain)", desc = "drain", long_desc = "Drain selected node" },
    },
    headers = {
      "NAME",
      "STATUS",
      "ROLES",
      "AGE",
      "VERSION",
      "INTERNAL-IP",
      "EXTERNAL-IP",
    },
    processRow = definition.processRow,
  },
}

function M.View(cancellationToken)
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
end

function M.Drain(node)
  local builder = ResourceBuilder:new("kubectl_drain")
  local node_def = {
    ft = "k8s_action",
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
  local def = {
    resource = "nodes |" .. node,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }

  ResourceBuilder:view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.resource,
      nil,
      node,
      M.definition.gvk.g,
      M.definition.gvk.v,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
