local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.pods.definition")
local hl = require("kubectl.actions.highlight")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local string_utils = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")

local M = {
  definition = definition,
  selection = {},
  pfs = {},
  tail_handle = nil,
  show_log_prefix = config.options.logs.prefix,
  log_since = config.options.logs.since,
  show_timestamps = config.options.logs.timestamps,
  show_previous = false,
}

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if state.instance[definition.resource] then
    state.instance[definition.resource]:draw(definition, cancellationToken)
    root_definition.setPortForwards(
      state.instance[definition.resource].extmarks,
      state.instance[definition.resource].prettyData,
      M.pfs
    )
  end
end

function M.TailLogs(pod, ns, container)
  pod = pod or M.selection.pod
  ns = ns or M.selection.ns
  container = container or M.selection.container
  local ntfy = " tailing: " .. pod

  local function stop_tailing()
    if M.tail_handle and not M.tail_handle:is_closing() then
      M.tail_handle:stop()
      M.tail_handle:close()
      vim.notify("Stopped" .. ntfy)
    end
  end
  if M.tail_handle and not M.tail_handle:is_closing() then
    stop_tailing()
    return
  end

  local logs_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  vim.api.nvim_win_set_cursor(logs_win, { vim.api.nvim_buf_line_count(buf), 0 })

  local function fetch_logs()
    commands.run_async("log_stream_async", {
      pod,
      ns,
      "1s",
      M.show_previous,
      M.show_timestamps,
      M.show_log_prefix,
    }, function(data)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, vim.split(data, "\n", { trimempty = true }))
          vim.api.nvim_set_option_value("modified", false, { buf = buf })
          if logs_win == vim.api.nvim_get_current_win() then
            vim.api.nvim_win_set_cursor(0, { line_count, 0 })
          end
        end
      end)
    end)
  end

  M.tail_handle = vim.uv.new_timer()
  M.tail_handle:start(0, 1000, function()
    fetch_logs()
  end)

  vim.schedule(function()
    vim.notify(ntfy)
  end)

  local group = vim.api.nvim_create_augroup("__kubectl_tailing", { clear = false })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      stop_tailing()
    end,
  })
  -- end
end

function M.selectPod(pod, ns)
  M.selection = { pod = pod, ns = ns, container = nil }
end

function M.Logs(reload)
  local def = {
    resource = "logs",
    ft = "k8s_pod_logs",
    syntax = "less",
    name = M.selection.pod,
    namespace = M.selection.ns,
    since = M.log_since,
    cmd = "log_stream_async",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. M.log_since .. "]" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix[" .. tostring(M.show_log_prefix) .. "]" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps[" .. tostring(M.show_timestamps) .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. tostring(M.show_previous) .. "]" },
    },
  }

  ResourceBuilder:view_float(def, {
    reload = reload,
    args = { def.name, def.namespace, def.since, M.show_previous, M.show_timestamps, M.show_log_prefix },
  })
end

function M.PortForward(pod, ns)
  local def = {
    ft = "k8s_action",
    display = "PF: " .. pod .. "-" .. "?",
    resource = pod,
    cmd = { "port-forward", pod, "-n", ns },
    resource_name = string_utils.capitalize(definition.resource_name),
    name = pod,
    ns = ns,
    group = definition.group,
    version = definition.version,
  }

  commands.run_async("get_async", {
    def.resource_name,
    def.ns,
    def.name,
    def.group,
    def.version,
    def.syntax,
  }, function(data)
    local containers = {}
    local builder = ResourceBuilder:new("kubectl_pf")
    builder.data = data
    builder:decodeJson()
    for _, container in ipairs(builder.data.spec.containers) do
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

    vim.schedule(function()
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

      builder:action_view(def, data, function(args)
        local client = require("kubectl_client")
        local local_port, remote_port = args[6]:match("(%d+):(%d+)")
        client.portforward_start("pod", args[2], args[4], local_port, remote_port)
      end)
    end)
  end)
end

function M.Desc(name, ns, reload)
  local def = {
    resource = "pods | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "pod", name, "-n", ns },
    syntax = "yaml",
    kind = "pods",
    cmd = "describe_async",
  }
  ResourceBuilder:view_float(def, { args = { def.kind, ns, name, definition.group }, reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
