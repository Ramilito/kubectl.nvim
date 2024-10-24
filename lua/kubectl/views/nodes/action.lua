local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local M = {}

function M.drain(node)
  local drain_args = {}
  local builder = ResourceBuilder:new("kubectl_drain")
  local win_config

  builder.buf_nr, win_config = buffers.confirmation_buffer(
    "Drain node: " .. node .. "?",
    "k8s_node_drain",
    function(confirm)
      if confirm then
        commands.shell_command_async("kubectl", drain_args)
      end
    end
  )

  vim.api.nvim_buf_attach(builder.buf_nr, false, {
    on_lines = function(_, buf_nr, _, first, last_orig, last_new, byte_count)
      if first == last_orig and last_orig == last_new and byte_count == 0 then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
      local grace_period, timeout, ignore_daemonset, delete_emptydir_data, force

      for _, line in ipairs(lines) do
        if line:match("Grace period:") then
          grace_period = line:match("Grace period:%s*(.*)")
        elseif line:match("Timeout:") then
          timeout = line:match("Timeout:%s*(.*)")
        elseif line:match("Ignore daemonset:") then
          ignore_daemonset = line:match("Ignore daemonset:%s*(.*)")
        elseif line:match("Delete emptydir data:") then
          delete_emptydir_data = line:match("Delete emptydir data:%s*(.*)")
        elseif line:match("Force:") then
          force = line:match("Force:%s*(.*)")
        end
      end

      local args = { "drain", "nodes/" .. node, "--grace-period", grace_period, "--timeout", timeout }

      if ignore_daemonset == "true" then
        table.insert(args, "--ignore-daemonsets")
      end
      if delete_emptydir_data == "true" then
        table.insert(args, "--delete-emptydir-data")
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
  local confirmation = "[y]es [n]o"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

  table.insert(builder.data, "Grace period: -1")
  table.insert(builder.data, "Timeout: 5s")
  table.insert(builder.data, "Ignore daemonset: false")
  table.insert(builder.data, "Delete emptydir data: false")
  table.insert(builder.data, "Force: false")
  table.insert(builder.data, "")
  table.insert(builder.data, "Args: ")
  table.insert(builder.data, padding .. confirmation)

  builder:setContentRaw()

  vim.cmd([[syntax match KubectlSuccess /.*:\@=/]])
  vim.cmd([[syntax match KubectlHeader /:\@<=.*/]])
end

return M
