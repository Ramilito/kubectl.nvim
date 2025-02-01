local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.pods.definition")
local hl = require("kubectl.actions.highlight")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  selection = {},
  pfs = {},
  tail_handle = nil,
  show_log_prefix = tostring(config.options.logs.prefix),
  log_since = config.options.logs.since,
  show_timestamps = tostring(config.options.logs.timestamps),
  show_previous = "false",
}

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
  root_definition.setPortForwards(state.instance.extmarks, state.instance.prettyData, M.pfs)
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

function M.Logs(reload)
  local def = {
    resource = "logs",
    ft = "k8s_pod_logs",
    url = {
      "logs",
      "-p=" .. M.show_previous,
      "--all-containers=true",
      "--since=" .. M.log_since,
      "--prefix=" .. M.show_log_prefix,
      "--timestamps=" .. M.show_timestamps,
      M.selection.pod,
      "-n",
      M.selection.ns,
    },
    syntax = "less",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. M.log_since .. "]" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix[" .. M.show_log_prefix .. "]" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps[" .. M.show_timestamps .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. M.show_previous .. "]" },
    },
  }

  if reload == false and M.tail_handle then
    M.tail_handle:kill(2)
    M.tail_handle = nil
    vim.schedule(function()
      M.TailLogs(M.selection.pod, M.selection.ns)
    end)
  end
  ResourceBuilder:view_float(def, { cmd = "kubectl", reload = reload })
end

function M.PortForward(pod, ns)
  local builder = ResourceBuilder:new("kubectl_pf")
  local pf_def = {
    ft = "k8s_pod_pf",
    display = "PF: " .. pod .. "-" .. "?",
    resource = pod,
    cmd = { "port-forward", "pods/" .. pod, "-n", ns },
  }

  local resource = tables.find_resource(state.instance.data, pod, ns)
  if not resource then
    return
  end
  local containers = {}
  for _, container in ipairs(resource.spec.containers) do
    if container.ports then
      for _, port in ipairs(container.ports) do
        local name
        if port.name and container.name then
          name = container.name .. "::(" .. port.name .. ")"
        elseif container.name then
          name = container.name
        else
          name = nil
        end

        table.insert(containers, {
          name = { value = name, symbol = hl.symbols.pending },
          port = { value = port.containerPort, symbol = hl.symbols.success },
          protocol = port.protocol,
        })
      end
    end
  end
  if next(containers) == nil then
    containers[1] = { port = { value = "" }, name = { value = "" } }
  end
  builder.data, builder.extmarks = tables.pretty_print(containers, { "NAME", "PORT", "PROTOCOL" })
  table.insert(builder.data, " ")

  local data = {
    {
      text = "address:",
      value = "localhost",
      options = { "localhost", "0.0.0.0" },
      cmd = "--address",
      type = "option",
    },
    { text = "local:", value = tostring(containers[1].port.value), cmd = "", type = "positional" },
    { text = "container port:", value = tostring(containers[1].port.value), cmd = ":", type = "merge_above" },
  }

  builder:action_view(pf_def, data, function(args)
    commands.shell_command_async("kubectl", args)
    vim.schedule(function()
      M.View()
    end)
  end)
end

function M.Desc(name, ns, reload)
  local def = {
    resource = "pod | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "pod", name, "-n", ns },
    syntax = "yaml",
  }
  ResourceBuilder:view_float(def, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
