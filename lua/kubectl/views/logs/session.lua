--- LogSession manager
--- Uses resource_manager for instance lifecycle, adds streaming-specific behavior
local client = require("kubectl.client")
local config = require("kubectl.config")
local manager = require("kubectl.resource_manager")

local M = {}

-- Key prefix for log sessions in the manager
local KEY_PREFIX = "log_session:"

---@class kubectl.LogSessionOptions
---@field since string Log history duration (e.g., "5m", "1h")
---@field prefix boolean Show container prefix
---@field timestamps boolean Show timestamps
---@field previous boolean Show previous container logs

-- Global options persist across sessions
local global_options = nil

local function get_default_options()
  return {
    since = config.options.logs.since,
    prefix = config.options.logs.prefix,
    timestamps = config.options.logs.timestamps,
    previous = false,
  }
end

local function session_key(buf)
  return KEY_PREFIX .. buf
end

--- Create a new log session instance (plain table)
---@param buf integer Buffer number
---@param win integer Window number
---@param options? kubectl.LogSessionOptions
---@return table session
local function create_session(buf, win, options)
  local defaults = get_default_options()
  local session = {
    rust_session = nil,
    timer = nil,
    options = vim.tbl_extend("force", defaults, options or {}),
    buf = buf,
    win = win,
    stopped = false,
  }

  --- Check if the session is currently active (streaming)
  function session:is_active()
    if self.stopped or not self.rust_session then
      return false
    end
    local ok, is_open = pcall(function()
      return self.rust_session:open()
    end)
    return ok and is_open
  end

  --- Stop the session and clean up resources
  function session:stop()
    if self.stopped then
      return
    end
    self.stopped = true

    if self.rust_session then
      pcall(function()
        self.rust_session:close()
      end)
      self.rust_session = nil
    end

    if self.timer and not self.timer:is_closing() then
      self.timer:stop()
      self.timer:close()
    end
    self.timer = nil

    -- Remove from manager
    manager.remove(session_key(buf))
  end

  --- Start streaming logs for the given pods
  ---@param pods table[] Array of {name, namespace} tables
  ---@param container string? Container name
  ---@return boolean success
  function session:start(pods, container)
    if self.stopped then
      return false
    end

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

    local timer = vim.uv.new_timer()
    self.timer = timer

    -- Capture self for timer callback
    local this = self
    timer:start(
      0,
      200,
      vim.schedule_wrap(function()
        if this.stopped then
          return
        end

        if not vim.api.nvim_buf_is_valid(this.buf) then
          this:stop()
          return
        end

        if not this:is_active() then
          this:stop()
          return
        end

        local read_ok, lines = pcall(function()
          return this.rust_session:read_chunk()
        end)
        if read_ok and lines and #lines > 0 then
          local start_line = vim.api.nvim_buf_line_count(this.buf)
          vim.api.nvim_buf_set_lines(this.buf, start_line, start_line, false, lines)
          vim.api.nvim_set_option_value("modified", false, { buf = this.buf })

          if vim.api.nvim_win_is_valid(this.win) and this.win == vim.api.nvim_get_current_win() then
            pcall(vim.api.nvim_win_set_cursor, this.win, { vim.api.nvim_buf_line_count(this.buf), 0 })
          end
        end
      end)
    )

    -- Cleanup on buffer close
    local group = vim.api.nvim_create_augroup("__kubectl_log_session_" .. self.buf, { clear = true })
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = group,
      buffer = self.buf,
      once = true,
      callback = function()
        this:stop()
      end,
    })

    return true
  end

  function session:get_options()
    return self.options
  end

  function session:set_options(opts)
    self.options = vim.tbl_extend("force", self.options, opts)
  end

  return session
end

-- Public API

--- Get or create a session for the given buffer
---@param buf integer Buffer number
---@param win integer Window number
---@param options? kubectl.LogSessionOptions
---@return table session
function M.get_or_create(buf, win, options)
  local key = session_key(buf)
  local existing = manager.get(key)
  if existing and not existing.stopped then
    return existing
  end
  -- Use manager with custom factory
  return manager.get_or_create(key, function()
    return create_session(buf, win, options)
  end)
end

--- Get an existing session for the buffer
---@param buf integer Buffer number
---@return table|nil session
function M.get(buf)
  local session = manager.get(session_key(buf))
  if session and not session.stopped then
    return session
  end
  return nil
end

--- Stop and remove session for the buffer
---@param buf integer Buffer number
function M.stop(buf)
  local session = manager.get(session_key(buf))
  if session then
    session:stop()
  end
end

--- Stop all active sessions
function M.stop_all()
  manager.foreach(KEY_PREFIX, function(_, session)
    session:stop()
  end)
end

--- Check if there's an active session for the buffer
---@param buf integer Buffer number
---@return boolean
function M.is_active(buf)
  local session = manager.get(session_key(buf))
  return session ~= nil and session:is_active()
end

--- Get current global options
---@param _ integer? Buffer number (ignored, kept for API compatibility)
---@return kubectl.LogSessionOptions
function M.get_options(_)
  if not global_options then
    global_options = get_default_options()
  end
  return vim.deepcopy(global_options)
end

--- Set global options
---@param options kubectl.LogSessionOptions Options to merge
function M.set_options(options)
  if not global_options then
    global_options = get_default_options()
  end
  global_options = vim.tbl_extend("force", global_options, options)
end

--- Reset global options to defaults
function M.reset_options()
  global_options = get_default_options()
end

return M
