local BaseResource = require("kubectl.resources.base_resource")
local config = require("kubectl.config")
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
---@param force_refresh boolean|nil If true, always get fresh selections
---@return table pods List of { name, namespace } entries
---@return string display_name Display name for the view
local function get_pods_for_logs(force_refresh)
  local current_buf = vim.api.nvim_get_current_buf()
  local current_ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If we're in the logs view and have cached pods, reuse them
  local cached_pods, cached_display, cached_source = log_session.get_cached_pods()
  if not force_refresh and current_ft == "k8s_pod_logs" and cached_pods and #cached_pods > 0 and cached_display then
    return cached_pods, cached_display
  end

  -- Get fresh selections from the source buffer (pods buffer)
  local source_buf = current_ft == "k8s_pod_logs" and cached_source or current_buf
  local selections = state.getSelections(source_buf)
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

function M.Logs()
  -- Stop any active session on current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  local current_ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
  log_session.stop(current_buf)

  -- If called from pods buffer, this is a fresh log view
  local source_buf = current_buf
  if current_ft == "k8s_pod_logs" then
    -- Reusing existing log view, get source from cache
    local _, _, cached_source = log_session.get_cached_pods()
    source_buf = cached_source or current_buf
  end

  local pods, display_name = get_pods_for_logs()

  -- Cache pods list for option changes (gh, gp, gt, etc.)
  log_session.set_cached_pods(pods, display_name, source_buf)

  local width = math.floor(config.options.float_size.width * vim.o.columns) - 4

  -- Get current options for display
  local opts = log_session.get_options()

  local builder = manager.get_or_create("pod_logs")
  builder.view_float({
    resource = "pod_logs",
    display_name = display_name,
    ft = "k8s_pod_logs",
    syntax = "k8s_pod_logs",
    cmd = "log_stream_async",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. tostring(opts.since) .. "]" },
      { key = "<Plug>(kubectl.prefix)", desc = "Prefix[" .. tostring(opts.prefix) .. "]" },
      { key = "<Plug>(kubectl.timestamps)", desc = "Timestamps[" .. tostring(opts.timestamps) .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. tostring(opts.previous) .. "]" },
      { key = "<Plug>(kubectl.expand_json)", desc = "Toggle JSON" },
    },
  }, {
    args = {
      pods = pods,
      container = M.selection.container,
      since = opts.since,
      previous = opts.previous,
      timestamps = opts.timestamps,
      prefix = opts.prefix,
      histogram_width = width,
    },
  })
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
