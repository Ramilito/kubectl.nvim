local client = require("kubectl.client")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local pf_view = require("kubectl.views.portforward")
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
      "CPU",
      "MEM",
      "%CPU/R",
      "%CPU/L",
      "%MEM/R",
      "%MEM/L",
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
    session = nil, ---@type kubectl.LogSession?
    timer = nil, ---@type any
    cleanup = nil, ---@type function?
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    local pfs = pf_view.getPFRows(string.lower(M.definition.gvk.k))
    builder.extmarks_extra = {}
    pf_view.setPortForwards(builder.extmarks_extra, builder.prettyData, pfs)
    builder.draw(cancellationToken)
  end
end

--- Stop any existing log session and timer
local function stop_log_session()
  -- Use cleanup function if available (handles the stopped flag)
  if M.log.cleanup then
    M.log.cleanup()
    M.log.cleanup = nil
    return
  end

  -- Fallback cleanup
  if M.log.session then
    pcall(function()
      M.log.session:close() ---@diagnostic disable-line: undefined-field
    end)
    M.log.session = nil
  end
  ---@diagnostic disable-next-line: undefined-field
  if M.log.timer and not M.log.timer:is_closing() then
    M.log.timer:stop() ---@diagnostic disable-line: undefined-field
    M.log.timer:close() ---@diagnostic disable-line: undefined-field
  end
  M.log.timer = nil
end

--- Start log polling for the given buffer/window
---@param buf integer
---@param win integer
local function start_log_polling(buf, win)
  local timer = vim.uv.new_timer()
  local stopped = false

  local function cleanup()
    if stopped then
      return
    end
    stopped = true
    if M.log.session then
      pcall(function()
        M.log.session:close() ---@diagnostic disable-line: undefined-field
      end)
    end
    if timer and not timer:is_closing() then ---@diagnostic disable-line: undefined-field
      timer:stop() ---@diagnostic disable-line: undefined-field
      timer:close() ---@diagnostic disable-line: undefined-field
    end
    M.log.session = nil
    M.log.timer = nil
    M.log.cleanup = nil
  end

  timer:start(
    0,
    200, -- 200ms polling interval
    vim.schedule_wrap(function()
      if stopped then
        return
      end

      -- Check if buffer is still valid
      if not vim.api.nvim_buf_is_valid(buf) then
        cleanup()
        return
      end

      -- Check if session is still open
      local session_open = false
      if M.log.session then
        local check_ok, is_open = pcall(function()
          return M.log.session:open() ---@diagnostic disable-line: undefined-field
        end)
        session_open = check_ok and is_open
      end

      if not session_open then
        cleanup()
        return
      end

      -- Read available log lines
      local read_ok, lines = pcall(function()
        return M.log.session:read_chunk() ---@diagnostic disable-line: undefined-field
      end)
      if read_ok and lines and #lines > 0 then
        local start_line = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, start_line, start_line, false, lines)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        -- Auto-scroll if user is still in the logs window
        if vim.api.nvim_win_is_valid(win) and win == vim.api.nvim_get_current_win() then
          pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(buf), 0 })
        end
      end
    end)
  )

  M.log.timer = timer
  M.log.cleanup = cleanup

  -- Cleanup on buffer close
  local group = vim.api.nvim_create_augroup("__kubectl_log_session", { clear = true })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = buf,
    once = true,
    callback = cleanup,
  })
end

function M.selectPod(pod, ns, container)
  M.selection = { pod = pod, ns = ns, container = container }
end

--- Build pods list from selections or single selection
---@return table pods List of { name, namespace } entries
---@return string display_name Display name for the view
local function get_pods_for_logs()
  local selections = state.getSelections()
  local pods = {}

  if #selections > 0 then
    for _, sel in ipairs(selections) do
      table.insert(pods, { name = sel.name, namespace = sel.namespace })
    end
    local display = #pods == 1 and pods[1].name or (#pods .. " pods")
    return pods, display
  end

  -- Fall back to single selection
  if M.selection.pod then
    table.insert(pods, { name = M.selection.pod, namespace = M.selection.ns })
    return pods, M.selection.pod .. " | " .. M.selection.ns
  end

  return pods, "No pods selected"
end

function M.Logs(_reload)
  stop_log_session()

  local pods, display_name = get_pods_for_logs()
  local width = math.floor(config.options.float_size.width * vim.o.columns) - 4

  local builder = manager.get_or_create("pod_logs")
  builder.view_float({
    resource = "pod_logs",
    display_name = display_name,
    ft = "k8s_pod_logs",
    syntax = "k8s_pod_logs",
    cmd = "log_stream_async",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. tostring(M.log.log_since) .. "]" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix[" .. tostring(M.log.show_log_prefix) .. "]" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps[" .. tostring(M.log.show_timestamps) .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. tostring(M.log.show_previous) .. "]" },
      { key = "<Plug>(kubectl.expand_json)", desc = "Toggle JSON" },
    },
  }, {
    args = {
      pods = pods,
      container = M.selection.container,
      since = M.log.log_since,
      previous = M.log.show_previous,
      timestamps = M.log.show_timestamps,
      prefix = M.log.show_log_prefix,
      histogram_width = width,
    },
  })
end

--- Toggle follow mode - stops current session or starts streaming from now
function M.TailLogs()
  local pods, display_name = get_pods_for_logs()

  -- If session exists and is following, stop it
  if M.log.session then
    stop_log_session()
    vim.notify("Stopped following: " .. display_name)
    return
  end

  if #pods == 0 then
    vim.notify("No pods selected", vim.log.levels.WARN)
    return
  end

  -- Start streaming from now (no historical logs, follow=true)
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  ---@type boolean, kubectl.LogSession?
  local ok, sess = pcall(client.log_session, {
    pods = pods,
    container = M.selection.container,
    timestamps = M.log.show_timestamps,
    follow = true,
    previous = false,
    prefix = M.log.show_log_prefix and true or nil,
  })
  if not ok or not sess then
    vim.notify("Failed to start log session: " .. tostring(sess), vim.log.levels.ERROR)
    return
  end
  M.log.session = sess ---@diagnostic disable-line: assign-type-mismatch

  -- Move cursor to end
  local line_count = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })

  -- Start polling
  start_log_polling(buf, win)
  vim.notify("Following: " .. display_name)
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
    gvk = M.definition.gvk,
    name = pod,
    namespace = ns,
    output = def.syntax,
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
        local address = args[1].value
        local local_port = args[2].value
        local remote_port = args[3].value
        client.portforward_start(M.definition.gvk.k, pod, ns, address, local_port, remote_port)
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
      context = state.context["current-context"],
      gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = ns,
      name = name,
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
