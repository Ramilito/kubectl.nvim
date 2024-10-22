local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
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
  local win_config

  builder.buf_nr, win_config = buffers.confirmation_buffer(
    "Drain node: " .. node .. "?",
    "k8s_node_drain",
    function(confirm)
      if confirm then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local grace_period, timeout, ignore_daemonset, delete_local_data, force

        for _, line in ipairs(lines) do
          if line:match("Grace period:") then
            grace_period = line:match("Grace period:%s*(.*)")
          elseif line:match("Timeout:") then
            timeout = line:match("Timeout:%s*(.*)")
          elseif line:match("Ignore daemonset:") then
            ignore_daemonset = line:match("Ignore daemonset:%s*(.*)")
          elseif line:match("Delete local data:") then
            delete_local_data = line:match("Delete local data:%s*(.*)")
          elseif line:match("Force:") then
            force = line:match("Force:%s*(.*)")
          end
        end

        local args = { "drain", "nodes/" .. node, "--grace-period", grace_period, "--timeout", timeout }

        if ignore_daemonset == "true" then
          table.insert(args, "--ignore-daemonsets")
        end
        if delete_local_data == "true" then
          table.insert(args, "--delete-local-data")
        end
        if force == "true" then
          table.insert(args, "--force")
        end

        vim.print(vim.inspect(args))
        -- commands.shell_command_async("kubectl", { "drain", "nodes/" .. node })
      end
    end
  )

  builder.data = {}
  local confirmation = "[y]es [n]o:"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

  table.insert(builder.data, "Grace period: -1")
  table.insert(builder.data, "Timeout: 5s")
  table.insert(builder.data, "Ignore daemonset: false")
  table.insert(builder.data, "Delete local data: false")
  table.insert(builder.data, "Force: false")
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
