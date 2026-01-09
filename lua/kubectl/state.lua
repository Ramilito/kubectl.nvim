local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local viewsTable = require("kubectl.utils.viewsTable")
local M = {}

---@type table
M.context = {}
---@type table
M.buffers = {}
---@type { client: { major: number, minor: number }, server: { major: number, minor: number } }
M.versions = { client = { major = 0, minor = 0 }, server = { major = 0, minor = 0 } }
---@type string
M.ns = ""
---@type string
M.filter = ""
---@type string
M.filter_key = ""
---@type string[]
M.filter_label = {}
---@type string[]
M.filter_history = {}
---@type string[]
M.filter_label_history = {}
---@type string[]
M.alias_history = {}
---@type string
M.proxyUrl = ""
---@type table<string, table<string, boolean>>
M.column_visibility = {}
---@type table<string, string[]>
M.column_order = {}

---------------------------------------------------------------------------
-- Per-buffer state for split support
-- Each buffer has its own marks, content_row_start, and selections
---------------------------------------------------------------------------
---@type table<number, { ns_id: number, header: number[], content_row_start: number, selections: table[] }>
M.buffer_state = {}

---------------------------------------------------------------------------
-- Global state (shared across all buffers)
---------------------------------------------------------------------------
---@type {[string]: { mark: table, current_word: string, order: "asc"|"desc" }}
M.sortby = {}
M.sortby_old = { current_word = "" }
---@type table
M.session = {
  contexts = {},
  filter_history = {},
  filter_label_history = {},
  alias_history = {},
  column_visibility = {},
  column_order = {},
}
---@type table
M.instance = {}
---@type table
M.instance_float = nil
---@type table
M.history = {}
---@type table
M.livez = { ok = nil, time_of_ok = os.time(), handle = nil }

local config_filename = "kubectl.json"

--- Decode a JSON string
--- @param string string The JSON string to decode
--- @return table|nil result The decoded table or nil if decoding fails
local decode = function(string)
  local success, result = pcall(vim.json.decode, string, { luanil = { object = true, array = true } })
  if success then
    return result
  else
    vim.schedule(function()
      vim.notify("Error: current-context unavailable", vim.log.levels.ERROR)
    end)
  end
end

--- Setup the kubectl state
function M.setup()
  vim.api.nvim_create_augroup("kubectl_session", { clear = true })

  -- Clean up buffer state when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = "kubectl_session",
    pattern = "kubectl://*",
    callback = function(args)
      M.clear_buffer_state(args.buf)
    end,
  })

  for k, _ in pairs(viewsTable) do
    M.sortby[k] = { mark = {}, current_word = "", order = "asc" }
  end

  commands.run_async("get_minified_config_async", {
    ctx_override = M.context["current-context"] or nil,
  }, function(data)
    local result = decode(data)
    if result then
      M.context = result
    end

    local cache = require("kubectl.cache")
    cache.LoadFallbackData()
    M.ns = M.session.namespace or config.options.namespace
    M.filter = ""
    M.versions = { client = { major = 0, minor = 0 }, server = { major = 0, minor = 0 } }
    vim.schedule(function()
      M.restore_session()
      M.checkHealth()
      if config.options.headers.skew.enabled then
        M.checkVersions()
      end
    end)
  end)
end

function M.checkVersions()
  commands.run_async("get_version_async", {}, function(data)
    local result = decode(data)
    if result then
      local clientVersion = result.clientVersion
      local serverVersion = result.serverVersion
      if not clientVersion or not serverVersion then
        return
      end
      M.versions.client.major = clientVersion.major
      M.versions.client.minor = clientVersion.minor
      M.versions.server.minor = serverVersion.minor
      M.versions.server.major = serverVersion.major
    else
      vim.schedule(function()
        require("kubectl.resources.contexts").View()
      end)
    end
  end)
end

function M.stop_livez()
  if M.livez.timer then
    M.livez.timer:stop()
  end
end

function M.checkHealth()
  M.livez.timer = vim.uv.new_timer()

  M.livez.timer:start(0, 2000, function()
    commands.run_async("get_server_raw_async", { path = "/livez" }, function(data)
      M.livez.ok = false
      if data == "ok" then
        M.livez.ok = true
        M.livez.time_of_ok = os.time()
      else
        M.livez.ok = false
      end
      vim.schedule(function()
        vim.cmd("doautocmd User K8sDataLoaded")
      end)
    end)
  end)
end

--- Get the current context
--- @return table context The current context
function M.getContext()
  return M.context
end

--- Get the current namespace
--- @return string ns The current namespace
function M.getNamespace()
  return M.ns
end

--- Get the current filter
--- @return string filter The current filter
function M.getFilter()
  return M.filter
end

--- Get the current filter_key
--- @return string filter_key The current filter
function M.getFilterKey()
  return M.filter_key
end

--- Get the current filter_label
--- @return string[] filter_label The current filter
function M.getFilterLabel()
  return M.filter_label
end

--- Get the current session_filter_label
--- @return string[] session_filter_label The current session filter label
function M.getSessionFilterLabel()
  return M.filter_label_history
end

--- Get the selections for the current buffer
--- @param bufnr number|nil Buffer number (optional, defaults to current buffer)
--- @return table selections The selections
function M.getSelections(bufnr)
  return M.get_buffer_selections(bufnr or vim.api.nvim_get_current_buf())
end

--- Get the current URL
--- @return string proxyurl The proxy URL
function M.getProxyUrl()
  return M.proxyUrl
end

--- Get the versions
--- @return table versions The versions
function M.getVersions()
  return M.versions
end

--- Set the filter pattern
--- @param pattern string The filter pattern to set
function M.setFilter(pattern)
  M.filter = pattern
end

--- Set the proxy URL
--- @param port number The port for the proxy URL
function M.setProxyUrl(port)
  M.proxyUrl = "http://127.0.0.1:" .. port
end

function M.reset_filters()
  M.filter_key = ""
  M.filter_label = {}
  M.filter_label_history = {}
end

--- Set the namespace
--- @param ns string The namespace to set
function M.setNS(ns)
  M.ns = ns
end

function M.setSortby(buf_name, word)
  M.sortby[buf_name] = { mark = {}, current_word = word, order = "asc" }
end

function M.addToHistory(new_view)
  if #M.history > 0 and M.history[#M.history] == new_view then
    return
  end
  table.insert(M.history, new_view)
end

function M.set_session(view)
  local session_name = M.context["current-context"]
  M.session.contexts[session_name] = { view = view, namespace = M.ns }
  M.session.filter_history = M.filter_history
  M.session.alias_history = M.alias_history
  M.session.filter_label_history = M.filter_label_history
  M.session.column_visibility = M.column_visibility
  M.session.column_order = M.column_order

  local config_file = commands.read_file(config_filename) or {}
  local merged = vim.tbl_deep_extend("force", config_file, M.session)
  commands.save_file(config_filename, merged)
end

function M.restore_session()
  local current_context = M.context["current-context"]
  local session_view = "pods"

  local ok, data_or_err = pcall(commands.read_file, config_filename)
  if ok and type(data_or_err) == "table" then
    M.session = data_or_err
    local ctx_session = M.session.contexts[current_context]
    if ctx_session then
      -- Found a saved context in the session file => restore from it
      M.ns = ctx_session.namespace
      M.filter_history = M.session.filter_history or {}
      M.alias_history = M.session.alias_history or {}
      M.filter_label_history = M.session.filter_label_history or {}
      M.column_visibility = M.session.column_visibility or {}
      M.column_order = M.session.column_order or {}
      session_view = ctx_session.view
    end
  end

  if not M.ns and current_context and M.context then
    local found_ns
    for _, item in ipairs(M.context.contexts or {}) do
      if item.name == current_context and item.context then
        found_ns = item.context.namespace
        break
      end
    end
    if found_ns then
      M.ns = found_ns
    end
  end

  if not M.ns then
    M.ns = "All"
  end

  require("kubectl.views").resource_or_fallback(session_view)
end

--- Get buffer-specific state, creating if needed
---@param bufnr number Buffer number
---@return { ns_id: number, header: number[], content_row_start: number, selections: table[] }
function M.get_buffer_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.buffer_state[bufnr] then
    M.buffer_state[bufnr] = {
      ns_id = 0,
      header = {},
      content_row_start = 0,
      selections = {},
    }
  end
  return M.buffer_state[bufnr]
end

--- Get selections for a buffer
---@param bufnr number Buffer number
---@return table[] selections
function M.get_buffer_selections(bufnr)
  return M.get_buffer_state(bufnr).selections
end

--- Set selections for a buffer
---@param bufnr number Buffer number
---@param selections table[] Array of selection objects
function M.set_buffer_selections(bufnr, selections)
  local buf_state = M.get_buffer_state(bufnr)
  buf_state.selections = selections
end

--- Clear buffer state when buffer is deleted
---@param bufnr number Buffer number
function M.clear_buffer_state(bufnr)
  M.buffer_state[bufnr] = nil
end

---------------------------------------------------------------------------
-- Picker Registry
-- Stores view recreation info, keyed by filetype:title for uniqueness
---------------------------------------------------------------------------

local SKIP_FILETYPES = {
  k8s_picker = true,
  k8s_namespaces = true,
  k8s_aliases = true,
  k8s_filter = true,
  k8s_filter_label = true,
  k8s_contexts = true,
  k8s_splash = true,
}

--- Build unique key from filetype and title
---@param filetype string
---@param title string
---@return string
local function make_key(filetype, title)
  return filetype .. ":" .. title
end

--- Register a view for the picker
---@param filetype string Filetype (e.g., "k8s_desc", "k8s_pod_logs")
---@param title string Display title (e.g., "pods | my-pod | default")
---@param open_func function Function to recreate the view
---@param args table Arguments for open_func
function M.picker_register(filetype, title, open_func, args)
  if not filetype or not title or not open_func then
    return
  end
  if SKIP_FILETYPES[filetype] then
    return
  end

  local key = make_key(filetype, title)
  local existing = M.buffers[key]

  M.buffers[key] = {
    key = key,
    filetype = filetype,
    title = title,
    open = open_func,
    args = args or {},
    tab_id = vim.api.nvim_get_current_tabpage(),
    created_at = existing and existing.created_at or os.time(),
  }
end

--- Remove a view from the picker by key
---@param key string The key (filetype:title)
function M.picker_remove(key)
  M.buffers[key] = nil
end

--- Get all picker entries sorted by creation time
---@return table[] Array of entries
function M.picker_list()
  local entries = {}
  for _, entry in pairs(M.buffers) do
    table.insert(entries, entry)
  end
  table.sort(entries, function(a, b)
    return (a.created_at or 0) < (b.created_at or 0)
  end)
  return entries
end

return M
