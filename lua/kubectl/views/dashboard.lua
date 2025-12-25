--- Dashboard view using native Neovim buffers instead of terminal.
--- This provides live ratatui rendering with full vim motion support.
local layout = require("kubectl.actions.layout")

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
    return ansi256_to_hex(tonumber(idx))
  end

  return nil
end

--- Register a highlight group for ratatui colors.
--- Converts ratatui-style names like "Ratatui_cyan_bold" to actual highlights.
---@param hl_name string
local function ensure_hl_group(hl_name)
  if registered_hl_groups[hl_name] then
    return
  end

  -- Parse the highlight name: Ratatui_<fg>[_on_<bg>][_bold][_italic][_underline]
  local fg, bg, bold, italic, underline

  -- Extract foreground color
  local fg_match = hl_name:match("^Ratatui_([^_]+)")
  if fg_match and fg_match ~= "reset" then
    fg = color_name_to_hex(fg_match)
  end

  -- Extract background color
  local bg_match = hl_name:match("_on_([^_]+)")
  if bg_match and bg_match ~= "reset" then
    bg = color_name_to_hex(bg_match)
  end

  -- Extract modifiers
  bold = hl_name:match("_bold") ~= nil
  italic = hl_name:match("_italic") ~= nil
  underline = hl_name:match("_underline") ~= nil

  -- Create the highlight group
  local hl_opts = {}
  if fg then
    hl_opts.fg = fg
  end
  if bg then
    hl_opts.bg = bg
  end
  if bold then
    hl_opts.bold = true
  end
  if italic then
    hl_opts.italic = true
  end
  if underline then
    hl_opts.underline = true
  end

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
---@param sess userdata Session object
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
  title = title or ("K8s " .. view_name:gsub("^%l", string.upper))

  -- Create buffer
  local bufname = "k8s_dashboard_" .. view_name
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "kubectl://" .. bufname)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "k8s_" .. view_name .. "_native")

  -- Create floating window
  local win = layout.float_layout(buf, "k8s_" .. view_name, title)
  layout.set_win_options(win)

  -- Enable cursorline for visual selection feedback
  vim.api.nvim_set_option_value("cursorline", true, { win = win })

  -- Enable native vim folding with custom foldexpr
  -- Namespace headers (no leading space) start folds, indented lines are fold content
  vim.api.nvim_set_option_value("foldmethod", "expr", { win = win })
  vim.api.nvim_set_option_value("foldexpr", "getline(v:lnum)=~'^\\s'?1:getline(v:lnum)=~'^$'?'=':'>1'", { win = win })
  vim.api.nvim_set_option_value("foldlevel", 99, { win = win }) -- Start fully expanded
  vim.api.nvim_set_option_value("foldminlines", 1, { win = win })

  -- Get window dimensions first
  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)

  -- Start the buffer-based dashboard session
  local client = require("kubectl.client")
  local ok, sess = pcall(client.start_buffer_dashboard, view_name)

  if not ok then
    vim.notify("Dashboard start failed: " .. tostring(sess), vim.log.levels.ERROR)
    vim.api.nvim_buf_delete(buf, { force = true })
    return
  end

  -- Send initial size immediately (Rust will adjust height based on content)
  sess:resize(win_width, win_height)

  -- Helper to push size on resize
  local function push_size()
    if vim.api.nvim_win_is_valid(win) then
      local w = vim.api.nvim_win_get_width(win)
      local h = vim.api.nvim_win_get_height(win)
      sess:resize(w, h)
    end
  end

  -- Setup keymaps
  setup_keymaps(buf, sess)

  -- Create autocmd group for cleanup
  local augroup = vim.api.nvim_create_augroup("KubectlDashboard_" .. buf, { clear = true })

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
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
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
        apply_frame(buf, frame)
      end

      -- Check if session closed
      if not sess:open() then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        cleanup()
      end
    end)
  )

  -- Handle manual window close
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(win),
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

  return buf, win
end

--- Open the Top view with native buffer rendering.
function M.top()
  return M.open("top", "K8s Top (Native)")
end

--- Open the Overview with native buffer rendering.
function M.overview()
  return M.open("overview", "K8s Overview (Native)")
end

return M
