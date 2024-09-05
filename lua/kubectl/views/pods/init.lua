local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")
local root_definition = require("kubectl.views.definition")
local tables = require("kubectl.utils.tables")

local M = {
  builder = nil,
  desc_builder = nil,
  log_builder = nil,
  selection = {},
  pfs = {},
  tail_handle = nil,
  -- TODO: should propably be configurable
  show_log_prefix = "true",
  show_timestamps = "true",
}

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true, "pods")
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Draw(cancellationToken)
  M.builder = M.builder:draw(definition, cancellationToken)
  root_definition.setPortForwards(M.builder.extmarks, M.builder.prettyData, M.pfs)
end

function M.TailLogs(pod, ns, container)
  pod = pod or M.selection.pod
  ns = ns or M.selection.ns
  container = container or M.selection.container
  local ntfy = " tailing: " .. pod
  local args = { "logs", "--follow", "--since=1s", pod, "-n", ns }
  if container then
    ntfy = ntfy .. " container: " .. container
    table.insert(args, "-c")
    table.insert(args, container)
  else
    table.insert(args, "--all-containers=true")
    table.insert(args, "--prefix=" .. M.show_log_prefix)
    table.insert(args, "--timestamps=" .. M.show_timestamps)
  end
  local buf = vim.api.nvim_get_current_buf()
  local logs_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(logs_win, { vim.api.nvim_buf_line_count(buf), 0 })

  local function handle_output(data)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, vim.split(data, "\n", { trimempty = true }))
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        if logs_win == vim.api.nvim_get_current_win() then
          vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
        end
      end
    end)
  end

  local function stop_tailing(handle)
    handle:kill(2)
    vim.notify("Stopped" .. ntfy, vim.log.levels.INFO)
  end

  local group = vim.api.nvim_create_augroup("__kubectl_tailing", { clear = false })
  if M.tail_handle and not M.tail_handle:is_closing() then
    vim.api.nvim_clear_autocmds({ group = group })
    stop_tailing(M.tail_handle)
  else
    M.tail_handle = commands.shell_command_async("kubectl", args, nil, handle_output)

    vim.notify("Started " .. ntfy, vim.log.levels.INFO)
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = group,
      buffer = buf,
      callback = function()
        stop_tailing(M.tail_handle)
      end,
    })
  end
end

function M.selectPod(pod, ns)
  M.selection = { pod = pod, ns = ns, container = nil }
end

function M.Logs()
  local def = {
    resource = "logs",
    ft = "k8s_pod_logs",
    url = {
      "logs",
      "--all-containers=true",
      "--prefix=" .. M.show_log_prefix,
      "--timestamps=" .. M.show_timestamps,
      M.selection.pod,
      "-n",
      M.selection.ns,
    },
    syntax = "less",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps" },
    },
  }

  if M.log_builder then
    M.log_builder:view_float(def, { cmd = "kubectl" })
  else
    M.log_builder = ResourceBuilder:view_float(def, { cmd = "kubectl" })
  end
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_pod_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "pod/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  local def = {
    resource = "desc",
    ft = "k8s_pod_desc",
    url = { "describe", "pod", name, "-n", ns },
    syntax = "yaml",
  }

  M.desc_builder = ResourceBuilder:view_float(def, { cmd = "kubectl" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
