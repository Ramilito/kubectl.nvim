--- DescribeSession manager
--- Uses resource_manager for instance lifecycle, adds polling-specific behavior
local buffers = require("kubectl.actions.buffers")
local client = require("kubectl.client")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

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

    -- Remove from manager
    manager.remove(session_key(buf))
  end

  --- Start the describe session
  ---@return boolean success
  function session:start()
    if self.stopped then
      return false
    end

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
          vim.api.nvim_buf_set_lines(this.buf, 0, -1, false, lines)
          vim.api.nvim_set_option_value("modified", false, { buf = this.buf })
        end
      end)
    )

    -- Cleanup on buffer close
    local group = vim.api.nvim_create_augroup("__kubectl_describe_session_" .. self.buf, { clear = true })
    vim.api.nvim_create_autocmd({ "BufWinLeave", "BufHidden", "BufUnload", "BufDelete" }, {
      group = group,
      buffer = self.buf,
      once = true,
      callback = function()
        this:stop()
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

--- Start a describe session for a resource (low-level, expects buffer to exist)
---@param name string Resource name
---@param namespace string|nil Namespace
---@param gvk table GVK {k, g, v}
---@param buf integer Buffer number
---@param win integer Window number
---@return boolean success
function M.start(name, namespace, gvk, buf, win)
  -- Stop any existing session for this buffer
  M.stop(buf)

  local args = {
    name = name,
    namespace = namespace or "",
    context = state.context["current-context"],
    gvk = gvk,
  }

  local session = M.get_or_create(buf, win, args)
  return session:start()
end

--- View describe output for a resource (handles buffer creation)
--- Similar to builder.view_float but for streaming describe sessions
---@param resource string Resource type (e.g., "pods", "deployments")
---@param name string Resource name
---@param namespace string|nil Namespace (nil for cluster-scoped)
---@param gvk table GVK {k, g, v}
---@return boolean success
function M.view(resource, name, namespace, gvk)
  local display_ns = namespace and (" | " .. namespace) or ""
  local title = resource .. " | " .. name .. display_ns

  -- Get or reuse existing window
  local builder = manager.get(resource .. "_desc")
  local existing_win = builder and builder.win_nr or nil

  -- Create floating buffer
  local buf, win = buffers.floating_buffer("k8s_desc", title, "yaml", existing_win)

  -- Store in manager for window reuse
  local new_builder = manager.get_or_create(resource .. "_desc")
  new_builder.buf_nr = buf
  new_builder.win_nr = win

  return M.start(name, namespace, gvk, buf, win)
end

return M
