--- DescribeSession manager
--- Handles polling-based describe with auto-refresh toggle
local buffers = require("kubectl.actions.buffers")
local client = require("kubectl.client")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

local KEY_PREFIX = "describe_session:"

local function session_key(buf)
  return KEY_PREFIX .. buf
end

--- Generate hints header with current auto-refresh state
---@param is_running boolean
---@return table header_lines, table header_marks
local function generate_header(is_running)
  local status = is_running and "on" or "off"
  local hints = {
    { key = "<Plug>(kubectl.refresh)", desc = "auto-refresh[" .. status .. "]" },
  }
  return tables.generateHeader(hints, false, false)
end

--- Create a new describe session instance
---@param buf integer Buffer number
---@param win integer Window number
---@param args table Describe arguments
---@return table session
local function create_session(buf, win, args)
  local session = {
    rust_session = nil,
    timer = nil,
    buf = buf,
    win = win,
    args = args,
    stopped = false,
    header_lines = nil,
    header_marks = nil,
  }

  function session:is_active()
    if self.stopped or not self.rust_session then
      return false
    end
    local ok, is_open = pcall(function()
      return self.rust_session:open()
    end)
    return ok and is_open
  end

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

  function session:update_header(is_running)
    self.header_lines, self.header_marks = generate_header(is_running)
  end

  function session:start()
    self.stopped = false
    self:update_header(true)

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
    self.timer = vim.uv.new_timer()

    local this = self
    self.timer:start(
      0,
      200,
      vim.schedule_wrap(function()
        if this.stopped or not vim.api.nvim_buf_is_valid(this.buf) or not this:is_active() then
          this:stop()
          manager.remove(session_key(this.buf))
          return
        end

        local read_ok, content = pcall(function()
          return this.rust_session:read_content()
        end)

        if read_ok and content then
          local lines = vim.split(content, "\n", { plain = true })
          buffers.set_content(this.buf, {
            content = lines,
            header = { data = this.header_lines, marks = this.header_marks },
          })
        end
      end)
    )

    -- Cleanup on buffer/window close
    vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWinLeave" }, {
      group = vim.api.nvim_create_augroup("__kubectl_describe_session_" .. self.buf, { clear = true }),
      buffer = self.buf,
      once = true,
      callback = function()
        this:stop()
        manager.remove(session_key(this.buf))
      end,
    })

    return true
  end

  function session:toggle()
    if self.stopped then
      self:start()
      return true
    else
      -- Update header before stopping so we can refresh display
      local old_header_count = self.header_lines and #self.header_lines or 0
      self:stop()
      self:update_header(false)

      -- Refresh display with paused header
      if vim.api.nvim_buf_is_valid(self.buf) then
        local current_lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
        local content = vim.list_slice(current_lines, old_header_count + 1)
        buffers.set_content(self.buf, {
          content = content,
          header = { data = self.header_lines, marks = self.header_marks },
        })
      end
      return false
    end
  end

  return session
end

-- Public API

--- View describe output for a resource
---@param resource string Resource type (e.g., "pods", "deployments")
---@param name string Resource name
---@param namespace string|nil Namespace (nil for cluster-scoped)
---@param gvk table GVK {k, g, v}
function M.view(resource, name, namespace, gvk)
  local display_ns = namespace and (" | " .. namespace) or ""
  local title = resource .. " | " .. name .. display_ns

  -- Get or reuse existing window
  local builder = manager.get(resource .. "_desc")
  local existing_win = builder and builder.win_nr or nil

  local buf, win = buffers.floating_buffer("k8s_desc", title, "yaml", existing_win)

  -- Store builder for window reuse
  local new_builder = manager.get_or_create(resource .. "_desc")
  new_builder.buf_nr = buf
  new_builder.win_nr = win
  new_builder.definition = {
    resource = resource .. "_desc",
    hints = { { key = "<Plug>(kubectl.refresh)", desc = "auto-refresh[on]" } },
  }

  -- Create and start session
  local key = session_key(buf)
  local session = manager.get_or_create(key, function()
    return create_session(buf, win, {
      name = name,
      namespace = namespace or "",
      context = state.context["current-context"],
      gvk = gvk,
    })
  end)
  session:start()
end

--- Toggle auto-refresh for the current buffer's describe session
---@param buf? integer Buffer number (defaults to current)
---@return boolean|nil is_running Whether session is now running, nil if no session
function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local session = manager.get(session_key(buf))
  if session then
    return session:toggle()
  end
  return nil
end

--- Stop all active describe sessions
function M.stop_all()
  manager.foreach(KEY_PREFIX, function(_, session)
    session:stop()
  end)
end

return M
