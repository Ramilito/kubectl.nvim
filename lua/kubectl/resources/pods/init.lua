local BaseResource = require("kubectl.resources.base_resource")
local log_session = require("kubectl.views.logs.session")
local manager = require("kubectl.resource_manager")
local pf_action = require("kubectl.actions.portforward")
local pf_view = require("kubectl.views.portforward")
local state = require("kubectl.state")

local resource = "pods"

local M = BaseResource.extend({
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
})

-- Pod-specific state (simple selection tracking)
M.selection = {}

function M.onBeforeDraw(builder)
  local pfs = pf_view.getPFRows(string.lower(M.definition.gvk.k))
  builder.extmarks_extra = {}
  pf_view.setPortForwards(builder.extmarks_extra, builder.prettyData, pfs)
end

function M.selectPod(pod, ns, container)
  M.selection = { pod = pod, ns = ns, container = container }
end

--- Build pods list from selections or single selection
---@return table pods List of { name, namespace } entries
---@return string display_name Display name for the view
local function get_pods_for_logs()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If in logs view, get pods from buffer variable
  if current_ft == "k8s_pod_logs" then
    local ok, pods = pcall(vim.api.nvim_buf_get_var, current_buf, "kubectl_log_pods")
    local ok2, display = pcall(vim.api.nvim_buf_get_var, current_buf, "kubectl_log_display")
    if ok and ok2 and pods and #pods > 0 then
      return pods, display
    end
  end

  -- Get from selections
  local selections = state.getSelections(current_buf)
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

--- Internal function that takes pods/display_name directly for recreation
---@param pods table[] Array of {name, namespace} tables
---@param display_name string Display name for the title
---@param container string|nil Container name
function M.LogsWithPods(pods, display_name, container)
  local buffers = require("kubectl.actions.buffers")
  local commands = require("kubectl.actions.commands")

  local current_buf = vim.api.nvim_get_current_buf()
  log_session.stop(current_buf)

  -- Close existing log frame if refreshing from within log view
  local builder = manager.get_or_create("pod_logs")
  if builder.frame then
    if builder.frame.hints_win and vim.api.nvim_win_is_valid(builder.frame.hints_win) then
      pcall(vim.api.nvim_win_close, builder.frame.hints_win, true)
    end
    for _, pane in ipairs(builder.frame.panes or {}) do
      if pane.win and vim.api.nvim_win_is_valid(pane.win) then
        pcall(vim.api.nvim_win_close, pane.win, true)
      end
    end
  end
  -- Get current options for display
  local opts = log_session.get_options()

  local ns = pods[1] and pods[1].namespace or ""
  local def = {
    resource = "pod_logs",
    ft = "k8s_pod_logs",
    title = "logs | " .. display_name .. " | " .. ns,
    syntax = "k8s_pod_logs",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. tostring(opts.since) .. "]" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix[" .. tostring(opts.prefix) .. "]" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps[" .. tostring(opts.timestamps) .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. tostring(opts.previous) .. "]" },
      { key = "<Plug>(kubectl.expand_json)", desc = "Toggle JSON" },
    },
    panes = {
      { title = "Logs" },
    },
  }

  builder.view_framed(def, {
    recreate_func = M.LogsWithPods,
    recreate_args = { pods, display_name, container },
  })

  -- Get actual window width after view is created, minus 2 for histogram borders
  local win = vim.fn.bufwinid(builder.buf_nr)
  local width = (win > 0 and vim.api.nvim_win_get_width(win) or 50) - 2

  -- Store pods in buffer for option changes (gp, gt, gh, etc.)
  vim.api.nvim_buf_set_var(builder.buf_nr, "kubectl_log_pods", pods)
  vim.api.nvim_buf_set_var(builder.buf_nr, "kubectl_log_display", display_name)

  -- Fetch initial logs (returns JSON-encoded array of strings)
  commands.run_async("log_stream_async", {
    pods = pods,
    container = container,
    since = opts.since,
    previous = opts.previous,
    timestamps = opts.timestamps,
    prefix = opts.prefix,
    histogram_width = width,
  }, function(result)
    if not result then
      return
    end
    builder.data = result
    builder.decodeJson()
    vim.schedule(function()
      buffers.set_content(builder.buf_nr, {
        content = builder.data,
        header = { data = {}, marks = {} },
      })
    end)
  end)
end

function M.Logs()
  local pods, display_name = get_pods_for_logs()
  M.LogsWithPods(pods, display_name, M.selection.container)
end

--- Toggle follow mode - stops current session or starts streaming from now
function M.TailLogs()
  local pods, display_name = get_pods_for_logs()

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  -- If session exists and is following, stop it
  if log_session.is_active(buf) then
    log_session.stop(buf)
    vim.notify("Stopped following: " .. display_name)
    return
  end

  if #pods == 0 then
    vim.notify("No pods selected", vim.log.levels.WARN)
    return
  end

  -- Get current options
  local opts = log_session.get_options(buf)

  -- Create and start new session
  local session = log_session.get_or_create(buf, win, opts)
  local success = session:start(pods, M.selection.container)

  if success then
    -- Move cursor to end
    local line_count = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
    vim.notify("Following: " .. display_name)
  end
end

function M.PortForward(pod, ns)
  pf_action.portforward("pod", M.definition.gvk, pod, ns)
end

return M
