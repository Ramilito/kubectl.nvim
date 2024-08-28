local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")
local root_definition = require("kubectl.views.definition")
local tables = require("kubectl.utils.tables")

local M = {
  builder = nil,
  selection = {},
  pfs = {},
  is_tailing = false,
  tail_handle = nil,
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
  local ntfy = " tailing: " .. pod .. " container: " .. container
  local args = { "logs", "--follow", "--since=1s", pod, "-n", ns, "-c", container }
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })

  local function handle_output(data)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, vim.split(data, "\n"))
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
      end
    end)
  end

  local function stop_tailing(handle)
    handle:kill(2)
    vim.notify("Stopped" .. ntfy, vim.log.levels.INFO)
  end

  local should_tail = not M.is_tailing
  local group = vim.api.nvim_create_augroup("__kubectl_tailing", { clear = false })
  if should_tail then
    M.is_tailing = true
    M.tail_handle = commands.shell_command_async("kubectl", args, nil, handle_output)

    vim.notify("Started " .. ntfy, vim.log.levels.INFO)
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = group,
      buffer = buf,
      callback = function()
        stop_tailing(M.tail_handle)
      end,
    })
  else
    M.is_tailing = false
    vim.api.nvim_clear_autocmds({ group = group })
    stop_tailing(M.tail_handle)
  end
end

function M.selectPod(pod, ns)
  local container
  local data = M.builder.data.items
  for _, p_data in ipairs(data) do
    if p_data.metadata.name == pod and p_data.metadata.namespace == ns and not M.selection.container then
      container = p_data.spec.containers[1].name
    end
  end
  M.selection = { pod = pod, ns = ns, container = container }
end

function M.Logs()
  if not M.builder or not M.builder.data.items then
    return
  end
  ResourceBuilder:view_float({
    resource = "logs",
    ft = "k8s_pod_logs",
    url = { "{{BASE}}/api/v1/namespaces/" .. M.selection.ns .. "/pods/" .. M.selection.pod .. "/log" .. "?pretty=true" },
    syntax = "less",
    hints = {
      { key = "<f>", desc = "Follow" },
      { key = "<gw>", desc = "Wrap" },
    },
  }, { contentType = "text/html" })
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_pod_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "pod/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:view_float({
    resource = "desc",
    ft = "k8s_pod_desc",
    url = { "describe", "pod", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
