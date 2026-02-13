--- DescribeSession manager
--- Handles polling-based describe with auto-refresh toggle
local buffers = require("kubectl.actions.buffers")
local loop = require("kubectl.utils.loop")
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
    buf = buf,
    win = win,
    args = args,
    builder = builder,
  }

  function session:is_active()
    if not self.rust_session then
      return false
    end
    local ok, is_open = pcall(function()
      return self.rust_session:open()
    end)
    return ok and is_open
  end

  function session:stop()
    loop.stop_loop(self.buf)

    if self.rust_session then
      pcall(function()
        self.rust_session:close()
      end)
      self.rust_session = nil
    end
  end

  function session:update_hints(is_running)
    if self.builder and self.builder.frame then
      self.builder.definition.hints = get_hints(is_running)
      self.builder.renderHints()
    end
  end

  function session:start()
    self:update_hints(true)

    local client = require("kubectl.client")
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

    local this = self
    loop.start_loop_for_buffer(self.buf, function(is_cancelled)
      -- Skip if cancelled (toggled off) or rust session closed
      if is_cancelled() or not this:is_active() then
        return
      end

      -- Buffer deleted - full cleanup
      if not vim.api.nvim_buf_is_valid(this.buf) then
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

      loop.set_running(this.buf, false)
    end, { interval = 200 })

    return true
  end

  function session:toggle()
    if loop.is_running(self.buf) then
      self:stop()
      self:update_hints(false)
      return false
    else
      self:start()
      return true
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
