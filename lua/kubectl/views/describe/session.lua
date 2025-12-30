--- DescribeSession manager
--- Uses resource_manager for instance lifecycle, adds polling-specific behavior
local buffers = require("kubectl.actions.buffers")
local client = require("kubectl.client")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

-- Key prefix for describe sessions in the manager
local KEY_PREFIX = "describe_session:"

local function session_key(buf)
  return KEY_PREFIX .. buf
end

--- Create a new describe session instance
---@param buf integer Buffer number
---@param win integer Window number
---@param args table Describe arguments (name, namespace, gvk, context)
---@return table session
local function create_session(buf, win, args)
  local session = {
    rust_session = nil,
    timer = nil,
    buf = buf,
    win = win,
    args = args,
    stopped = false,
    header_lines = nil, -- Hints header lines
    header_marks = nil, -- Hints header extmarks
  }

  --- Check if the session is currently active
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

    ---@diagnostic disable: undefined-field
    if self.timer and not self.timer:is_closing() then
      self.timer:stop()
      self.timer:close()
    end
    ---@diagnostic enable: undefined-field
    self.timer = nil
  end

  --- Toggle the session on/off
  ---@return boolean is_running Whether session is now running
  function session:toggle()
    if self.stopped then
      self.stopped = false
      self:start()
      return true
    else
      self:stop()
      return false
    end
  end

  --- Start the describe session
  ---@return boolean success
  function session:start()
    -- Reset stopped state when starting
    self.stopped = false

    local ok, sess = pcall(client.describe_session, {
      name = self.args.name,
      namespace = self.args.namespace,
      context = self.args.context,
      gvk = self.args.gvk,
    })

    if not ok or not sess then
      vim.notify("Failed to start describe session: " .. tostring(sess), vim.log.levels.ERROR)
      return false
    end

    self.rust_session = sess

    local timer = vim.uv.new_timer()
    self.timer = timer

    -- Capture self for timer callback
    local this = self
    timer:start(
      0,
      200, -- Poll every 200ms for new content
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

        local read_ok, content = pcall(function()
          return this.rust_session:read_content()
        end)

        if read_ok and content then
          -- Replace buffer content with new describe output
          local lines = vim.split(content, "\n", { plain = true })
          buffers.set_content(this.buf, {
            content = lines,
            header = {
              data = this.header_lines,
              marks = this.header_marks,
            },
          })
        end
      end)
    )

    -- Cleanup on buffer/window close
    local group = vim.api.nvim_create_augroup("__kubectl_describe_session_" .. self.buf, { clear = true })
    vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWinLeave" }, {
      group = group,
      buffer = self.buf,
      once = true,
      callback = function()
        this:stop()
        manager.remove(session_key(self.buf))
      end,
    })

    return true
  end

  return session
end

-- Public API

--- Get or create a session for the given buffer
---@param buf integer Buffer number
---@param win integer Window number
---@param args table Describe arguments
---@return table session
function M.get_or_create(buf, win, args)
  local key = session_key(buf)
  local existing = manager.get(key)
  if existing and not existing.stopped then
    return existing
  end
  return manager.get_or_create(key, function()
    return create_session(buf, win, args)
  end)
end

--- Get an existing session for the buffer
---@param buf integer Buffer number
---@return table|nil session
function M.get(buf)
  return manager.get(session_key(buf))
end

--- Stop and remove session for the buffer
---@param buf integer Buffer number
function M.stop(buf)
  local session = manager.get(session_key(buf))
  if session then
    session:stop()
  end
end

--- Stop all active describe sessions
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

--- Setup and start a describe session for a resource (low-level, expects buffer to exist)
---@param name string Resource name
---@param namespace string|nil Namespace
---@param gvk table GVK {k, g, v}
---@param buf integer Buffer number
---@param win integer Window number
---@param base_title? string Base title for window (without state indicator)
---@param header_lines? table Hints header lines
---@param header_marks? table Hints header extmarks
---@return boolean success
function M.setup(name, namespace, gvk, buf, win, base_title, header_lines, header_marks)
  -- Stop any existing session for this buffer
  M.stop(buf)

  local args = {
    name = name,
    namespace = namespace or "",
    context = state.context["current-context"],
    gvk = gvk,
  }

  local session = M.get_or_create(buf, win, args)
  session.base_title = base_title
  session.header_lines = header_lines
  session.header_marks = header_marks
  return session:start()
end

--- Generate hints with current auto-refresh state
---@param is_running boolean Whether auto-refresh is running
---@return table hints, table header_lines, table header_marks
local function generate_hints(is_running)
  local status = is_running and "on" or "off"
  local hints = {
    { key = "<Plug>(kubectl.refresh)", desc = "auto-refresh[" .. status .. "]" },
  }
  local header_lines, header_marks = tables.generateHeader(hints, false, false)
  return hints, header_lines, header_marks
end

--- View describe output for a resource (handles buffer creation)
--- Creates the buffer, starts the session with auto-refresh
---@param resource string Resource type (e.g., "pods", "deployments")
---@param name string Resource name
---@param namespace string|nil Namespace (nil for cluster-scoped)
---@param gvk table GVK {k, g, v}
function M.view(resource, name, namespace, gvk)
  local display_ns = namespace and (" | " .. namespace) or ""
  local base_title = resource .. " | " .. name .. display_ns

  -- Get or reuse existing window
  local builder = manager.get(resource .. "_desc")
  local existing_win = builder and builder.win_nr or nil

  -- Create floating buffer
  local buf, win = buffers.floating_buffer("k8s_desc", base_title, "yaml", existing_win)

  -- Generate hints header with initial state (running)
  local hints, header_lines, header_marks = generate_hints(true)

  -- Store in manager for window reuse and set definition with hints
  local new_builder = manager.get_or_create(resource .. "_desc")
  new_builder.buf_nr = buf
  new_builder.win_nr = win
  new_builder.definition = {
    resource = resource .. "_desc",
    hints = hints,
  }

  M.setup(name, namespace, gvk, buf, win, base_title, header_lines, header_marks)
end

--- Toggle auto-refresh for the current buffer's describe session
---@param buf? integer Buffer number (defaults to current)
---@return boolean|nil is_running Whether session is now running, nil if no session
function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local session = M.get(buf)
  if session then
    local is_running = session:toggle()
    -- Update hints to reflect new state
    local old_header_count = session.header_lines and #session.header_lines or 0
    local _, header_lines, header_marks = generate_hints(is_running)
    session.header_lines = header_lines
    session.header_marks = header_marks
    -- Refresh buffer header immediately if paused (no timer running)
    if not is_running and vim.api.nvim_buf_is_valid(session.buf) then
      local current_lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
      -- Skip old header lines to get content
      local content = vim.list_slice(current_lines, old_header_count + 1)
      buffers.set_content(session.buf, {
        content = content,
        header = {
          data = header_lines,
          marks = header_marks,
        },
      })
    end
    return is_running
  end
  return nil
end

return M
