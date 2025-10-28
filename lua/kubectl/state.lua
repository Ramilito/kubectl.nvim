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
---@type number
M.content_row_start = 0
---@type table
M.marks = { ns_id = 0, header = {} }
---@type table
M.selections = {}
---@type {[string]: { mark: table, current_word: string, order: "asc"|"desc" }}
M.sortby = {}
M.sortby_old = { current_word = "" }
---@type table
M.session = { contexts = {}, filter_history = {}, filter_label_history = {}, alias_history = {} }
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

    -- local cache = require("kubectl.cache")
    -- cache.LoadFallbackData()
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

--- Get the selections
--- @return table selections The selections
function M.getSelections()
  return M.selections
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

function M.set_buffer_state(buf, filetype, open_func, args)
  local function valid()
    return filetype ~= "k8s_picker"
      and filetype ~= "k8s_namespaces"
      and filetype ~= "k8s_aliases"
      and filetype ~= "k8s_filter"
      and filetype ~= "k8s_contexts"
      and filetype ~= "k8s_splash"
      and not M.buffers[buf]
  end

  if not valid() then
    return
  end

  local current_tab = vim.api.nvim_get_current_tabpage()
  M.buffers[buf] = { open = open_func, args = args, tab_id = current_tab }
end

return M
