local commands = require("kubectl.actions.commands")
local viewsTable = require("kubectl.utils.viewsTable")
local M = {}

---@type table
M.context = {}
---@type { client: { major: number, minor: number }, server: { major: number, minor: number } }
M.versions = { client = { major = 0, minor = 0 }, server = { major = 0, minor = 0 } }
---@type string
M.ns = ""
---@type string
M.filter = ""
---@type string[]
M.filter_history = {}
---@type string[]
M.alias_history = {}
---@type string
M.proxyUrl = ""
---@type number
M.content_row_start = 0
---@type table
M.marks = { ns_id = 0, header = {} }
---@type {[string]: { mark: table, current_word: string, order: "asc"|"desc" }}
M.sortby = {}
M.sortby_old = { current_word = "" }
---@type table
M.session = { contexts = {}, filter_history = {}, alias_history = {} }
---@type table
M.instance = nil
---@type table
M.instance_float = nil
---@type table
M.history = {}
---@type table
M.livez = { ok = nil, time_of_ok = os.time() }

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
  local config = require("kubectl.config")

  for k, _ in pairs(viewsTable) do
    M.sortby[k] = { mark = {}, current_word = "", order = "asc" }
  end

  commands.shell_command_async("kubectl", { "config", "view", "--minify", "-o", "json" }, function(data)
    local result = decode(data)
    if result then
      M.context = result
    end

    M.ns = M.session.namespace or config.options.namespace
    M.filter = ""
    M.versions = { client = { major = 0, minor = 0 }, server = { major = 0, minor = 0 } }
    vim.schedule(function()
      M.restore_session()
      M.checkVersions()
      M.checkHealth(function()
        if
          M.versions.client.major == 0
          or M.versions.server.major == 0
          or M.versions.client.minor == 0
          or M.versions.server.minor == 0
        then
          M.checkVersions()
        end
      end)
    end)
  end)
end

function M.checkVersions()
  -- get client and server version
  commands.shell_command_async("kubectl", { "version", "--output", "json" }, function(data)
    local result = decode(data)
    if result then
      local clientVersion = result.clientVersion.gitVersion
      local serverVersion = result.serverVersion.gitVersion
      if not clientVersion or not serverVersion then
        return
      end
      M.versions.client.major = tonumber(string.match(clientVersion, "(%d+)%..*")) or 0
      M.versions.server.major = tonumber(string.match(serverVersion, "(%d+)%..*")) or 0
      M.versions.client.minor = tonumber(string.match(clientVersion, "%d+%.(%d+)%..*")) or 0
      M.versions.server.minor = tonumber(string.match(serverVersion, "%d+%.(%d+)%..*")) or 0
    end
  end)
end

function M.checkHealth(cb)
  local timer = vim.uv.new_timer()
  local ResourceBuilder = require("kubectl.resourcebuilder")
  local builder = ResourceBuilder:new("health_check"):setCmd({ "{{BASE}}/livez" }, "curl")

  timer:start(0, 5000, function()
    builder:fetchAsync(
      function(self)
        if self.data == "ok" then
          M.livez.ok = true
          M.livez.time_of_ok = os.time()
          if cb then
            cb()
          end
        else
          M.livez.ok = false
        end
      end,
      nil,
      function(_)
        M.livez.ok = false
      end,
      { timeout = 5000 }
    )
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

--- Set the namespace
--- @param ns string The namespace to set
function M.setNS(ns)
  M.ns = ns
end

function M.addToHistory(new_view)
  if #M.history > 0 and M.history[#M.history] == new_view then
    return
  end
  table.insert(M.history, new_view)
end

function M.set_session()
  local session_name = M.context["current-context"]
  local ok, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
  if ok then
    M.session.contexts[session_name] = { view = buf_name, namespace = M.ns }
  end
  M.session.filter_history = M.filter_history
  M.session.alias_history = M.alias_history
  commands.save_config("kubectl.json", M.session)
end

function M.restore_session()
  local config = commands.load_config("kubectl.json")
  local current_context = M.context["current-context"]
  if config then
    if config.contexts then
      M.session.contexts = config.contexts
    end
    if config.filter_history then
      M.session.filter_history = config.filter_history
    end
    if config.alias_history then
      M.session.alias_history = config.alias_history
    end
  end

  if not M.session.contexts or not M.session.contexts[current_context] then
    M.session.contexts[current_context] = { view = "pods", namespace = "All" }
  end

  -- Restore state
  M.ns = M.session.contexts[current_context].namespace
  M.filter_history = M.session.filter_history
  M.alias_history = M.session.alias_history

  -- change view
  local session_view = M.session.contexts[current_context].view
  require("kubectl.views").view_or_fallback(session_view)
end

return M
