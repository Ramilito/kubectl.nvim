local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local pf_definition = require("kubectl.views.port_forwards.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "pods"

---@class PodsModule : Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "Pod" },
    hints = {
      { key = "<Plug>(kubectl.logs)", desc = "logs", long_desc = "Shows logs for all containers in pod" },
      { key = "<Plug>(kubectl.select)", desc = "containers", long_desc = "Opens container view" },
      { key = "<Plug>(kubectl.portforward)", desc = "PF", long_desc = "View active Port forwards" },
      { key = "<Plug>(kubectl.kill)", desc = "delete pod", long_desc = "Delete pod" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "READY",
      "STATUS",
      "RESTARTS",
      "IP",
      "NODE",
      "AGE",
    },
  },
  selection = {},
  log = {
    log_since = config.options.logs.since,
    show_log_prefix = config.options.logs.prefix,
    show_previous = false,
    show_timestamps = config.options.logs.timestamps,
    tail_handle = nil,
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    local pfs = pf_definition.getPFRows()
    builder.extmarks_extra = {}
    pf_definition.setPortForwards(builder.extmarks_extra, builder.prettyData, pfs)
    builder.draw(cancellationToken)
  end
end

function M.TailLogs(pod, ns, container)
  pod = pod or M.selection.pod
  ns = ns or M.selection.ns
  container = container or M.selection.container
  local ntfy = " tailing: " .. pod

  local function stop_tailing()
    if M.log.tail_handle and not M.log.tail_handle:is_closing() then
      M.log.tail_handle:stop()
      M.log.tail_handle:close()
      vim.notify("Stopped" .. ntfy)
    end
  end
  if M.log.tail_handle and not M.log.tail_handle:is_closing() then
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
      container,
      "1s",
      M.log.show_previous,
      M.log.show_timestamps,
      M.log.show_log_prefix,
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

  M.log.tail_handle = vim.uv.new_timer()
  M.log.tail_handle:start(0, 1000, function()
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

function M.selectPod(pod, ns, container)
  M.selection = { pod = pod, ns = ns, container = container }
end

function M.Logs(reload)
  local def = {
    resource = "pod_logs",
    display_name = M.selection.pod .. " | " .. M.selection.ns,
    ft = "k8s_pod_logs",
    syntax = "less",
    cmd = "log_stream_async",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. M.log.log_since .. "]" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix[" .. tostring(M.log.show_log_prefix) .. "]" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps[" .. tostring(M.log.show_timestamps) .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. tostring(M.log.show_previous) .. "]" },
    },
  }

  local logsBuilder = manager.get_or_create("pod_logs")

  logsBuilder.view_float(def, {
    reload = reload,
    args = {
      M.selection.pod,
      M.selection.ns,
      M.selection.container,
      M.log.log_since,
      M.log.show_previous,
      M.log.show_timestamps,
      M.log.show_log_prefix,
    },
  })
end

function M.PortForward(pod, ns)
  local def = {
    resource = "pod_pf",
    display = "PF: " .. pod .. "-" .. "?",
    ft = "k8s_action",
    ns = ns,
    group = M.definition.group,
    version = M.definition.version,
  }

  commands.run_async("get_single_async", {
    M.definition.gvk.k,
    ns,
    pod,
    def.syntax,
  }, function(data)
    local containers = {}
    local pfBuilder = manager.get_or_create(def.resource)
    pfBuilder.data = data
    pfBuilder.decodeJson()
    for _, container in ipairs(pfBuilder.data.spec.containers) do
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
      pfBuilder.data, pfBuilder.extmarks = tables.pretty_print(containers, { "NAME", "PORT", "PROTOCOL" })
      table.insert(pfBuilder.data, " ")

      local pf_data = {
        {
          text = "address:",
          value = "localhost",
          options = { "localhost", "0.0.0.0" },
          cmd = "",
          type = "positional",
        },
        { text = "local:", value = tostring(containers[1].port.value), cmd = "", type = "positional" },
        { text = "container port:", value = tostring(containers[1].port.value), cmd = ":", type = "merge_above" },
      }

      pfBuilder.action_view(def, pf_data, function(args)
        local client = require("kubectl.client")
        local local_port = args[2].value
        local remote_port = args[3].value
        client.portforward_start(M.definition.gvk.k, pod, ns, args[1], local_port, remote_port)
      end)
    end)
  end)
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }
  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.resource,
      ns,
      name,
      M.definition.gvk.g,
      M.definition.gvk.v,
    },
    reload = reload,
  })
end

--- Get current selection for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
