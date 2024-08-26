local commands = require("kubectl.actions.commands")
local viewsTable = require("kubectl.utils.viewsTable")
local M = {}

---@type table
M.context = {}
---@type string
M.ns = ""
---@type string
M.filter = ""
---@type string[]
M.filter_history = {}
---@type string
M.proxyUrl = ""
---@type table
M.notifications = {}
---@type number
M.content_row_start = 0
---@type table
M.marks = { ns_id = 0, header = {} }
---@type {[string]: { mark: table, current_word: string, order: "asc"|"desc" }}
M.sortby = {}
M.sortby_old = { current_word = "" }
---@type table
M.session = { contexts = { default = { view = "pods", namespace = "All" } }, filter_history = {} }

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
    vim.schedule(function()
      M.restore_session()
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

--- Get the current URL
--- @return string proxyurl The proxy URL
function M.getProxyUrl()
  return M.proxyUrl
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

function M.set_session()
  local session_name = M.getContext().contexts[1].name
  local ok, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
  if ok then
    M.session.contexts[session_name] = { view = buf_name }
  end
  M.session.contexts[session_name].namespace = M.ns
  M.session.filter_history = M.filter_history
  commands.save_config("kubectl.json", M.session)
end

function M.restore_session()
  local config = commands.load_config("kubectl.json")

  if config then
    M.session = config
  end

  -- Restore state
  local context_table = M.session.contexts[M.getContext().contexts[1].name] or M.session.contexts.default
  M.ns = context_table.namespace
  M.filter_history = M.session.filter_history

  -- change view
  local session_view = context_table.view
  require("kubectl.views").view_or_fallback(session_view)
end

return M
