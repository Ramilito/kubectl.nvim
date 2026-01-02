--- DescribeSession manager
--- Handles polling-based describe with auto-refresh toggle
local buffers = require("kubectl.actions.buffers")
local client = require("kubectl.client")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local M = {}

local KEY_PREFIX = "describe_session:"

local function session_key(buf)
  return KEY_PREFIX .. buf
end

--- Generate hints for the framed layout
---@param is_running boolean
---@return table hints
local function get_hints(is_running)
  local status = is_running and "on" or "off"
  return {
    { key = "<Plug>(kubectl.refresh)", desc = "auto-refresh[" .. status .. "]" },
  }
end

--- Create a new describe session instance
---@param buf integer Buffer number
---@param win integer Window number
---@param args table Describe arguments
---@param builder table Resource builder
---@return table session
local function create_session(buf, win, args, builder)
  local session = {
    rust_session = nil,
    timer = nil,
    buf = buf,
    win = win,
    args = args,
    builder = builder,
    stopped = false,
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

  function session:update_hints(is_running)
    if self.builder and self.builder.frame then
      self.builder.definition.hints = get_hints(is_running)
      self.builder.renderHints()
    end
  end

  function session:start()
    self.stopped = false
    self:update_hints(true)

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
    ---@diagnostic disable: undefined-field
    self.timer:start(
      0,
      200,
      vim.schedule_wrap(function()
        -- If intentionally stopped by user toggle, just return without removing session
        if this.stopped then
          return
        end

        -- If buffer invalid or rust session closed, clean up fully
        if not vim.api.nvim_buf_is_valid(this.buf) or not this:is_active() then
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
            header = { data = {}, marks = {} },
          })
        end
      end)
    )
    ---@diagnostic enable: undefined-field

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
      self:stop()
      self:update_hints(false)
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

  local definition = {
    resource = resource .. "_desc",
    ft = "k8s_desc",
    title = title,
    syntax = "yaml",
    hints = get_hints(true),
    panes = {
      { title = "Describe" },
    },
  }

  local builder = manager.get_or_create(definition.resource)
  builder.view_framed(definition, {
    recreate_func = M.view,
    recreate_args = { resource, name, namespace, gvk },
  })

  -- Create and start session
  local key = session_key(builder.buf_nr)
  local session = manager.get_or_create(key, function()
    return create_session(builder.buf_nr, builder.win_nr, {
      name = name,
      namespace = namespace or "",
      context = state.context["current-context"],
      gvk = gvk,
    }, builder)
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
