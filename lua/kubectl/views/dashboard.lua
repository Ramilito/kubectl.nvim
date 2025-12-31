--- Dashboard view using native Neovim buffers instead of terminal.
--- This provides live ratatui rendering with full vim motion support.
local buffers = require("kubectl.actions.buffers")
local manager = require("kubectl.resource_manager")

local M = {}

-- Namespace for dashboard extmarks
local ns_id = vim.api.nvim_create_namespace("__kubectl_dashboard")

-- Cache for registered highlight groups
local registered_hl_groups = {}

--- Convert ANSI 256 color index to hex.
---@param idx number
---@return string
local function ansi256_to_hex(idx)
  -- Standard colors
  local standard = {
    [0] = "#000000",
    [1] = "#800000",
    [2] = "#008000",
    [3] = "#808000",
    [4] = "#000080",
    [5] = "#800080",
    [6] = "#008080",
    [7] = "#c0c0c0",
    [8] = "#808080",
    [9] = "#ff0000",
    [10] = "#00ff00",
    [11] = "#ffff00",
    [12] = "#0000ff",
    [13] = "#ff00ff",
    [14] = "#00ffff",
    [15] = "#ffffff",
  }

  if standard[idx] then
    return standard[idx]
  end

  -- 216 color cube (16-231)
  if idx >= 16 and idx <= 231 then
    local n = idx - 16
    local b = (n % 6) * 51
    local g = (math.floor(n / 6) % 6) * 51
    local r = math.floor(n / 36) * 51
    return string.format("#%02x%02x%02x", r, g, b)
  end

  -- Grayscale (232-255)
  if idx >= 232 and idx <= 255 then
    local gray = (idx - 232) * 10 + 8
    return string.format("#%02x%02x%02x", gray, gray, gray)
  end

  return "#808080" -- fallback
end

--- Convert color name to hex value.
---@param name string
---@return string|nil
local function color_name_to_hex(name)
  -- Colors synced with lua/kubectl/actions/highlight.lua
  local colors = {
    black = "#000000",
    red = "#D16969", -- KubectlError
    green = "#608B4E", -- KubectlInfo
    yellow = "#DCDCAA", -- KubectlDebug
    blue = "#569CD6", -- KubectlHeader
    magenta = "#C586C0", -- KubectlPending
    cyan = "#4EC9B0", -- KubectlSuccess
    gray = "#666666", -- KubectlGray
    darkgray = "#404040",
    lightred = "#D16969", -- Same as error
    lightgreen = "#608B4E", -- Same as info
    lightyellow = "#D19A66", -- KubectlWarning (orange)
    lightblue = "#9CDCFE", -- KubectlNote
    lightmagenta = "#C586C0", -- Same as pending
    lightcyan = "#4EC9B0", -- Same as success
    white = "#FFFFFF", -- KubectlWhite
  }

  if colors[name] then
    return colors[name]
  end

  -- RGB hex (x followed by 6 hex chars)
  local hex = name:match("^x(%x%x%x%x%x%x)$")
  if hex then
    return "#" .. hex
  end

  -- Indexed color (i followed by number)
  local idx = name:match("^i(%d+)$")
  if idx then
    return ansi256_to_hex(tonumber(idx) --[[@as number]])
  end

  return nil
end

--- Ensure a highlight group exists for dashboard rendering.
---
--- Native Kubectl* groups (emitted by Rust for common colors) are already
--- defined by the plugin. Ratatui_* groups (fallback for unmapped colors)
--- are created dynamically from parsed color names.
---@param hl_name string
local function ensure_hl_group(hl_name)
  if registered_hl_groups[hl_name] then
    return
  end

  -- Native Kubectl* highlights are defined in highlight.lua (including Bold variants)
  if hl_name:match("^Kubectl") then
    registered_hl_groups[hl_name] = true
    return
  end

  -- Parse Ratatui_<fg>[_on_<bg>][_bold][_italic][_underline] format
  local fg_match = hl_name:match("^Ratatui_([^_]+)")
  local bg_match = hl_name:match("_on_([^_]+)")

  local fg = fg_match and fg_match ~= "reset" and color_name_to_hex(fg_match) or nil
  local bg = bg_match and bg_match ~= "reset" and color_name_to_hex(bg_match) or nil

  local hl_opts = {
    fg = fg,
    bg = bg,
    bold = hl_name:match("_bold") ~= nil or nil,
    italic = hl_name:match("_italic") ~= nil or nil,
    underline = hl_name:match("_underline") ~= nil or nil,
  }

  if next(hl_opts) then
    vim.api.nvim_set_hl(0, hl_name, hl_opts)
  end

  registered_hl_groups[hl_name] = true
end

--- Apply a rendered frame to a buffer.
---@param buf number Buffer number
---@param frame table Frame with lines and marks
local function apply_frame(buf, frame)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Convert frame.lines table to array if needed
  local lines = {}
  if frame.lines then
    for i = 1, #frame.lines do
      lines[i] = frame.lines[i] or ""
    end
  end

  -- Set lines
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Clear old extmarks
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  -- Apply new extmarks
  for _, mark in ipairs(frame.marks or {}) do
    if mark.hl_group then
      -- Ensure the highlight group exists
      ensure_hl_group(mark.hl_group)

      -- Apply the extmark
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, mark.row, mark.start_col, {
        end_col = mark.end_col,
        hl_group = mark.hl_group,
      })
    end
  end
end

--- Create keymaps for dashboard navigation.
--- Uses native vim motions and folding - only special keys are mapped.
---@param buf number Buffer number
---@param sess kubectl.DashboardSession Session object
local function setup_keymaps(buf, sess)
  local opts = { buffer = buf, noremap = true, silent = true }

  -- Helper to send key to Rust and poll for frame update
  local function send_key(key)
    local bytes = vim.api.nvim_replace_termcodes(key, true, true, true)
    sess:write(bytes)

    -- Poll for updated frame
    vim.defer_fn(function()
      local frame = sess:read_frame()
      if frame then
        apply_frame(buf, frame)
      end
    end, 10)
  end

  -- Helper to send cursor position to Rust (0-indexed)
  local function send_cursor()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- Convert to 0-indexed
    local cursor_msg = string.format("\x00CURSOR:%d\x00", cursor_line)
    sess:write(cursor_msg)
  end

  -- Tab switching and help
  for _, key in ipairs({ "<Tab>", "<S-Tab>", "?" }) do
    vim.keymap.set("n", key, function()
      send_key(key)
    end, opts)
  end

  -- Pod expansion (needs cursor sync)
  vim.keymap.set("n", "K", function()
    send_cursor()
    send_key("K")
  end, opts)

  -- Drift/general: refresh and filter
  vim.keymap.set("n", "r", function()
    send_key("r")
  end, opts)

  vim.keymap.set("n", "f", function()
    send_key("f")
  end, opts)

  -- Quit with q
  vim.keymap.set("n", "q", function()
    sess:write("q")
    sess:close()
  end, opts)
end

--- Create a dashboard view with native buffer rendering.
---@param view_name string The view name ("top" or "overview")
---@param title string|nil Optional title for the window
function M.open(view_name, title)
  local definition = {
    display_name = view_name,
    resource = "dashbaord",
    ft = "k8s_" .. view_name,
    syntax = "",
    title = title or "dashboard",
  }

  local builder = manager.get_or_create(definition.resource)
  builder.buf_nr, builder.win_nr =
    buffers.floating_buffer(definition.ft, definition.title, definition.syntax, builder.win_nr)

  -- Enable native vim folding with custom foldexpr
  -- Namespace headers (no leading space) start folds, indented lines are fold content
  vim.api.nvim_set_option_value("foldmethod", "expr", { win = builder.win_nr })
  vim.api.nvim_set_option_value(
    "foldexpr",
    "getline(v:lnum)=~'^\\s'?1:getline(v:lnum)=~'^$'?'=':'>1'",
    { win = builder.win_nr }
  )
  vim.api.nvim_set_option_value("foldlevel", 99, { win = builder.win_nr }) -- Start fully expanded
  vim.api.nvim_set_option_value("foldminlines", 1, { win = builder.win_nr })

  vim.schedule(function()
    -- Get window dimensions first
    local win_width = vim.api.nvim_win_get_width(builder.win_nr)
    local win_height = vim.api.nvim_win_get_height(builder.win_nr)

    -- Start the buffer-based dashboard session
    local client = require("kubectl.client")
    local ok, sess = pcall(client.start_buffer_dashboard, view_name, nil)

    if not ok then
      vim.notify("Dashboard start failed: " .. tostring(sess), vim.log.levels.ERROR)
      vim.api.nvim_buf_delete(builder.buf_nr, { force = true })
      return
    end
    ---@cast sess kubectl.DashboardSession

    -- Send initial size immediately (Rust will adjust height based on content)
    sess:resize(win_width, win_height)

    -- Helper to push size on resize
    local function push_size()
      if vim.api.nvim_win_is_valid(builder.win_nr) then
        local w = vim.api.nvim_win_get_width(builder.win_nr)
        local h = vim.api.nvim_win_get_height(builder.win_nr)
        sess:resize(w, h)
      end
    end

    -- Setup keymaps
    setup_keymaps(builder.buf_nr, sess)

    -- Create autocmd group for cleanup
    local augroup = vim.api.nvim_create_augroup("KubectlDashboard_" .. builder.buf_nr, { clear = true })

    -- Handle resize
    vim.api.nvim_create_autocmd("WinResized", {
      group = augroup,
      callback = function()
        push_size()
      end,
    })

    -- Cleanup function
    local function cleanup()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
      if vim.api.nvim_buf_is_valid(builder.buf_nr) then
        vim.api.nvim_buf_delete(builder.buf_nr, { force = true })
      end
    end

    -- Poll for frames (less frequently to reduce lag)
    local timer = vim.uv.new_timer()
    timer:start(
      0,
      100, -- 10fps - sufficient for live updates without lag
      vim.schedule_wrap(function()
        -- Read all available frames (use latest)
        local frame
        repeat
          local new_frame = sess:read_frame()
          if new_frame then
            frame = new_frame
          end
        until not new_frame

        -- Apply the latest frame
        if frame then
          apply_frame(builder.buf_nr, frame)
        end

        -- Check if session closed
        if not sess:open() then
          timer:stop()
          if not timer:is_closing() then
            timer:close()
          end
          if vim.api.nvim_win_is_valid(builder.win_nr) then
            vim.api.nvim_win_close(builder.win_nr, true)
          end
          cleanup()
        end
      end)
    )

    -- Handle manual window close
    vim.api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      pattern = tostring(builder.win_nr),
      once = true,
      callback = function()
        sess:close()
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        cleanup()
      end,
    })
  end)

  return builder.buf_nr, builder.win_nr
end

function M.top()
  return M.open("top", "K8s Top")
end

function M.overview()
  return M.open("overview", "K8s Overview")
end

--- Open the drift view with the specified path.
---@param path string|nil Path to diff against the cluster (nil to prompt for path)
function M.drift(path)
  local definition = {
    display_name = "drift",
    resource = "dashboard",
    ft = "k8s_drift",
    syntax = "",
    title = "Drift",
  }

  local builder = manager.get_or_create(definition.resource)
  builder.buf_nr, builder.win_nr =
    buffers.floating_buffer(definition.ft, definition.title, definition.syntax, builder.win_nr)

  local captured_path = path or ""
  vim.schedule(function()
    local win_width = vim.api.nvim_win_get_width(builder.win_nr)
    local win_height = vim.api.nvim_win_get_height(builder.win_nr)

    -- Start the buffer-based dashboard session with path argument
    local client = require("kubectl.client")
    local ok, sess = pcall(client.start_buffer_dashboard, "drift", captured_path)

    if not ok then
      vim.notify("Drift view start failed: " .. tostring(sess), vim.log.levels.ERROR)
      vim.api.nvim_buf_delete(builder.buf_nr, { force = true })
      return
    end
    ---@cast sess kubectl.DashboardSession

    -- Track current path for the path picker (closure variable, not on userdata)
    local current_drift_path = captured_path

    -- Send initial size immediately
    sess:resize(win_width, win_height)

    -- Helper to push size on resize
    local function push_size()
      if vim.api.nvim_win_is_valid(builder.win_nr) then
        local w = vim.api.nvim_win_get_width(builder.win_nr)
        local h = vim.api.nvim_win_get_height(builder.win_nr)
        sess:resize(w, h)
      end
    end

    -- Setup keymaps
    setup_keymaps(builder.buf_nr, sess)

    -- Drift-specific: path picker keymap
    vim.keymap.set("n", "p", function()
      vim.ui.input({
        prompt = "Drift path: ",
        default = current_drift_path,
        completion = "file",
      }, function(new_path)
        if new_path and new_path ~= "" then
          -- Expand vim shortcuts like %, %:h, ~
          new_path = vim.fn.expand(new_path)
          -- Update closure variable
          current_drift_path = new_path
          -- Send new path to Rust
          local path_msg = string.format("\x00PATH:%s\x00", new_path)
          sess:write(path_msg)
          -- Poll for updated frame
          vim.defer_fn(function()
            local frame = sess:read_frame()
            if frame then
              apply_frame(builder.buf_nr, frame)
            end
          end, 50)
        end
      end)
    end, { buffer = builder.buf_nr, noremap = true, silent = true })

    -- Create autocmd group for cleanup
    local augroup = vim.api.nvim_create_augroup("KubectlDrift_" .. builder.buf_nr, { clear = true })

    -- Handle resize
    vim.api.nvim_create_autocmd("WinResized", {
      group = augroup,
      callback = function()
        push_size()
      end,
    })

    -- Sync cursor position on movement to update diff preview
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup,
      buffer = builder.buf_nr,
      callback = function()
        local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
        local cursor_msg = string.format("\x00CURSOR:%d\x00", cursor_line)
        sess:write(cursor_msg)
        -- Poll for updated frame
        vim.defer_fn(function()
          local frame = sess:read_frame()
          if frame then
            apply_frame(builder.buf_nr, frame)
          end
        end, 10)
      end,
    })

    -- Cleanup function
    local function cleanup()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
      if vim.api.nvim_buf_is_valid(builder.buf_nr) then
        vim.api.nvim_buf_delete(builder.buf_nr, { force = true })
      end
    end

    -- Poll for frames
    local timer = vim.uv.new_timer()
    timer:start(
      0,
      100,
      vim.schedule_wrap(function()
        local frame
        repeat
          local new_frame = sess:read_frame()
          if new_frame then
            frame = new_frame
          end
        until not new_frame

        if frame then
          apply_frame(builder.buf_nr, frame)
        end

        if not sess:open() then
          timer:stop()
          if not timer:is_closing() then
            timer:close()
          end
          if vim.api.nvim_win_is_valid(builder.win_nr) then
            vim.api.nvim_win_close(builder.win_nr, true)
          end
          cleanup()
        end
      end)
    )

    -- Handle manual window close
    vim.api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      pattern = tostring(builder.win_nr),
      once = true,
      callback = function()
        sess:close()
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        cleanup()
      end,
    })
  end)

  return builder.buf_nr, builder.win_nr
end

return M
