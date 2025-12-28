--- LogSession manager
--- Encapsulates log streaming session state and lifecycle
local client = require("kubectl.client")
local config = require("kubectl.config")

---@class kubectl.LogSessionManager
---@field private _sessions table<integer, kubectl.LogSessionInstance> Buffer-keyed sessions
---@field private _global_options kubectl.LogSessionOptions? Global options that persist across sessions
local LogSessionManager = {
  _sessions = {},
  _global_options = nil, -- Lazy initialized
}

---@class kubectl.LogSessionOptions
---@field since string Log history duration (e.g., "5m", "1h")
---@field prefix boolean Show container prefix
---@field timestamps boolean Show timestamps
---@field previous boolean Show previous container logs

---@class kubectl.LogSessionInstance
---@field rust_session kubectl.LogSession? The Rust log session
---@field options kubectl.LogSessionOptions Session options
---@field buf integer Buffer number
---@field win integer Window number
---@field stopped boolean Whether the session has been stopped
---@field cleanup function? Cleanup function
local LogSessionInstance = {}
LogSessionInstance.__index = LogSessionInstance

--- Create a new LogSessionInstance
---@param buf integer Buffer number
---@param win integer Window number
---@param options? kubectl.LogSessionOptions
---@return kubectl.LogSessionInstance
function LogSessionInstance.new(buf, win, options)
  local defaults = {
    since = config.options.logs.since,
    prefix = config.options.logs.prefix,
    timestamps = config.options.logs.timestamps,
    previous = false,
  }

  local self = setmetatable({
    rust_session = nil,
    timer = nil,
    options = vim.tbl_extend("force", defaults, options or {}),
    buf = buf,
    win = win,
    stopped = false,
    cleanup = nil,
  }, LogSessionInstance)

  return self
end

--- Check if the session is currently active (streaming)
---@return boolean
function LogSessionInstance:is_active()
  if self.stopped then
    return false
  end
  if not self.rust_session then
    return false
  end
  local ok, is_open = pcall(function()
    return self.rust_session:open()
  end)
  return ok and is_open
end

--- Stop the session and clean up resources
function LogSessionInstance:stop()
  if self.stopped then
    return
  end
  self.stopped = true

  -- Close Rust session
  if self.rust_session then
    pcall(function()
      self.rust_session:close()
    end)
    self.rust_session = nil
  end

  -- Stop and close timer
  if self.timer and not self.timer:is_closing() then
    self.timer:stop()
    self.timer:close()
  end
  self.timer = nil
  self.cleanup = nil
end

--- Start streaming logs for the given pods
---@param pods table[] Array of {name, namespace} tables
---@param container string? Container name
---@return boolean success
function LogSessionInstance:start(pods, container)
  if self.stopped then
    return false
  end

  -- Create Rust log session
  local ok, sess = pcall(client.log_session, {
    pods = pods,
    container = container,
    timestamps = self.options.timestamps,
    follow = true,
    previous = false,
    prefix = self.options.prefix and true or nil,
  })

  if not ok or not sess then
    vim.notify("Failed to start log session: " .. tostring(sess), vim.log.levels.ERROR)
    return false
  end

  self.rust_session = sess

  -- Create cleanup function
  local function cleanup()
    self:stop()
    -- Remove from manager
    LogSessionManager._sessions[self.buf] = nil
  end
  self.cleanup = cleanup

  -- Start polling timer
  local timer = vim.uv.new_timer()
  self.timer = timer

  timer:start(
    0,
    200, -- 200ms polling interval
    vim.schedule_wrap(function()
      if self.stopped then
        return
      end

      -- Check if buffer is still valid
      if not vim.api.nvim_buf_is_valid(self.buf) then
        cleanup()
        return
      end

      -- Check if session is still open
      if not self:is_active() then
        cleanup()
        return
      end

      -- Read available log lines
      local read_ok, lines = pcall(function()
        return self.rust_session:read_chunk()
      end)
      if read_ok and lines and #lines > 0 then
        local start_line = vim.api.nvim_buf_line_count(self.buf)
        vim.api.nvim_buf_set_lines(self.buf, start_line, start_line, false, lines)
        vim.api.nvim_set_option_value("modified", false, { buf = self.buf })

        -- Auto-scroll if user is still in the logs window
        if vim.api.nvim_win_is_valid(self.win) and self.win == vim.api.nvim_get_current_win() then
          pcall(vim.api.nvim_win_set_cursor, self.win, { vim.api.nvim_buf_line_count(self.buf), 0 })
        end
      end
    end)
  )

  -- Setup autocmd for cleanup on buffer close
  local group = vim.api.nvim_create_augroup("__kubectl_log_session_" .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = self.buf,
    once = true,
    callback = cleanup,
  })

  return true
end

--- Get the log session options
---@return kubectl.LogSessionOptions
function LogSessionInstance:get_options()
  return self.options
end

--- Update session options
---@param options kubectl.LogSessionOptions
function LogSessionInstance:set_options(options)
  self.options = vim.tbl_extend("force", self.options, options)
end

-- LogSessionManager methods

--- Get or create a session for the given buffer
---@param buf integer Buffer number
---@param win integer Window number
---@param options? kubectl.LogSessionOptions
---@return kubectl.LogSessionInstance
function LogSessionManager.get_or_create(buf, win, options)
  local existing = LogSessionManager._sessions[buf]
  if existing and not existing.stopped then
    return existing
  end

  local session = LogSessionInstance.new(buf, win, options)
  LogSessionManager._sessions[buf] = session
  return session
end

--- Get an existing session for the buffer
---@param buf integer Buffer number
---@return kubectl.LogSessionInstance?
function LogSessionManager.get(buf)
  local session = LogSessionManager._sessions[buf]
  if session and not session.stopped then
    return session
  end
  return nil
end

--- Stop and remove session for the buffer
---@param buf integer Buffer number
function LogSessionManager.stop(buf)
  local session = LogSessionManager._sessions[buf]
  if session then
    session:stop()
    LogSessionManager._sessions[buf] = nil
  end
end

--- Stop all active sessions
function LogSessionManager.stop_all()
  for buf, session in pairs(LogSessionManager._sessions) do
    session:stop()
    LogSessionManager._sessions[buf] = nil
  end
end

--- Check if there's an active session for the buffer
---@param buf integer Buffer number
---@return boolean
function LogSessionManager.is_active(buf)
  local session = LogSessionManager._sessions[buf]
  return session ~= nil and session:is_active()
end

--- Get default options from config
---@return kubectl.LogSessionOptions
local function get_default_options()
  return {
    since = config.options.logs.since,
    prefix = config.options.logs.prefix,
    timestamps = config.options.logs.timestamps,
    previous = false,
  }
end

--- Initialize global options if not already set
local function ensure_global_options()
  if not LogSessionManager._global_options then
    LogSessionManager._global_options = get_default_options()
  end
  return LogSessionManager._global_options
end

--- Get current global options (persisted across sessions)
---@param _ integer? Buffer number (optional, ignored - kept for API compatibility)
---@return kubectl.LogSessionOptions
function LogSessionManager.get_options(_)
  -- Always return global options to maintain state across buffer closures
  return vim.deepcopy(ensure_global_options())
end

--- Set global options (persisted across sessions)
---@param options kubectl.LogSessionOptions Options to merge
function LogSessionManager.set_options(options)
  local global = ensure_global_options()
  LogSessionManager._global_options = vim.tbl_extend("force", global, options)
end

--- Reset global options to defaults
function LogSessionManager.reset_options()
  LogSessionManager._global_options = get_default_options()
end

return LogSessionManager
