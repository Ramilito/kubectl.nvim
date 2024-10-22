local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.nodes.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  grace_period = "-1",
  timeout = "5s",
  ignore_daemonset = "false",
  delete_local_data = "false",
  force = "false",
}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.Drain(node)
  local builder = ResourceBuilder:new("kubectl_drain")
  local win_config

  builder.buf_nr, win_config = buffers.confirmation_buffer("Drain node: " .. node .. "?", "", function(confirm)
    if confirm then
      -- commands.shell_command_async("kubectl", { "drain", "nodes/" .. node })
    end
  end)

  builder.data = {}
  local confirmation = "[y]es [n]o:"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

  table.insert(builder.data, "GracePeriod: " .. M.grace_period)
  table.insert(builder.data, "Timeout: " .. M.timeout)
  table.insert(builder.data, "Ignore Daemonset: " .. M.ignore_daemonset)
  table.insert(builder.data, "Delete local data: " .. M.delete_local_data)
  table.insert(builder.data, "Force: " .. M.force)
  table.insert(builder.data, padding .. confirmation)

  builder:setContentRaw()
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
