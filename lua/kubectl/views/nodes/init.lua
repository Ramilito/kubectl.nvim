local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.nodes.definition")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

local function add_row(builder, text, value)
  table.insert(builder.data, text .. value)
  local row = #builder.data - 1
  local line_length = #builder.data[#builder.data]

  table.insert(builder.extmarks, {
    row = row,
    start_col = 0,
    end_col = line_length - #value,
    hl_group = hl.symbols.header,
  })
  table.insert(builder.extmarks, {
    row = row,
    start_col = line_length - #value,
    end_col = line_length,
    hl_group = hl.symbols.success,
  })
end

function M.Drain(node)
  local drain_args = {}
  local builder = ResourceBuilder:new("kubectl_drain")
  local win_config

  builder.buf_nr, win_config = buffers.confirmation_buffer(
    "Drain node: " .. node .. "?",
    "k8s_node_drain",
    function(confirm)
      if confirm then
        commands.shell_command_async("kubectl", M.drain_args)
      end
    end
  )

  vim.api.nvim_buf_attach(builder.buf_nr, false, {
    on_lines = function(_, buf_nr, _, first, last_orig, last_new, byte_count)
      if first == last_orig and last_orig == last_new and byte_count == 0 then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
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

      if table.concat(drain_args, " ") ~= table.concat(args, " ") then
        for i, line in ipairs(lines) do
          if line:match("^Args:") then
            vim.schedule(function()
              pcall(vim.api.nvim_buf_set_text, buf_nr, i - 1, #"Args: ", i - 1, -1, { table.concat(args, " ") })
            end)
            break
          end
        end
      end
      drain_args = args
    end,
  })

  builder.data = {}
  builder.extmarks = {}
  local confirmation = "[y]es [n]o:"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

  add_row(builder, "Grace period: ", "-1")
  add_row(builder, "Timeout: ", "5s")
  add_row(builder, "Ignore daemonset: ", "false")
  add_row(builder, "Delete local data: ", "false")
  add_row(builder, "Force: ", "false")
  table.insert(builder.data, "")
  add_row(builder, "Args: ", "")
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
