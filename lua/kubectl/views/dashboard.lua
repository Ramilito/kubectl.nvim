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

  if idx >= 16 and idx <= 231 then
    local n = idx - 16
    local b = (n % 6) * 51
    local g = (math.floor(n / 6) % 6) * 51
    local r = math.floor(n / 36) * 51
    return string.format("#%02x%02x%02x", r, g, b)
  end

  if idx >= 232 and idx <= 255 then
    local gray = (idx - 232) * 10 + 8
    return string.format("#%02x%02x%02x", gray, gray, gray)
  end

  return "#808080"
end

--- Convert color name to hex value.
---@param name string
---@return string|nil
local function color_name_to_hex(name)
  local colors = {
    black = "#000000",
    red = "#D16969",
    green = "#608B4E",
    yellow = "#DCDCAA",
    blue = "#569CD6",
    magenta = "#C586C0",
    cyan = "#4EC9B0",
    gray = "#666666",
    darkgray = "#404040",
    lightred = "#D16969",
    lightgreen = "#608B4E",
    lightyellow = "#D19A66",
    lightblue = "#9CDCFE",
    lightmagenta = "#C586C0",
    lightcyan = "#4EC9B0",
    white = "#FFFFFF",
  }

  if colors[name] then
    return colors[name]
  end

  local hex = name:match("^x(%x%x%x%x%x%x)$")
  if hex then
    return "#" .. hex
  end

  local idx = name:match("^i(%d+)$")
  if idx then
    return ansi256_to_hex(tonumber(idx) --[[@as number]])
  end

  return nil
end

--- Ensure a highlight group exists for dashboard rendering.
---@param hl_name string
local function ensure_hl_group(hl_name)
  if registered_hl_groups[hl_name] then
    return
  end

  if hl_name:match("^Kubectl") then
    registered_hl_groups[hl_name] = true
    return
  end

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

  local lines = {}
  if frame.lines then
    for i = 1, #frame.lines do
      lines[i] = frame.lines[i] or ""
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  for _, mark in ipairs(frame.marks or {}) do
    if mark.hl_group then
      ensure_hl_group(mark.hl_group)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, mark.row, mark.start_col, {
        end_col = mark.end_col,
        hl_group = mark.hl_group,
      })
    end
  end
end

---@class DashboardOpts
---@field view_name string View name for the session
---@field view_args? string Optional arguments for the view
---@field title string Window title
---@field ft string Filetype for the buffer
---@field enable_folding? boolean Enable vim folding (default false)

--- Create a dashboard session with common boilerplate.
---@param opts DashboardOpts
---@return number buf_nr
---@return number win_nr
local function create_dashboard(opts)
  local builder = manager.get_or_create("dashboard")
  builder.buf_nr, builder.win_nr = buffers.floating_buffer(opts.ft, opts.title, "", builder.win_nr)

  if opts.enable_folding then
    vim.api.nvim_set_option_value("foldmethod", "expr", { win = builder.win_nr })
    vim.api.nvim_set_option_value(
      "foldexpr",
      "getline(v:lnum)=~'^\\s'?1:getline(v:lnum)=~'^$'?'=':'>1'",
      { win = builder.win_nr }
    )
    vim.api.nvim_set_option_value("foldlevel", 99, { win = builder.win_nr })
    vim.api.nvim_set_option_value("foldminlines", 1, { win = builder.win_nr })
  end

  vim.schedule(function()
    local win_width = vim.api.nvim_win_get_width(builder.win_nr)
    local win_height = vim.api.nvim_win_get_height(builder.win_nr)

    local client = require("kubectl.client")
    local ok, sess = pcall(client.start_buffer_dashboard, opts.view_name, opts.view_args)

    if not ok then
      vim.notify("Dashboard start failed: " .. tostring(sess), vim.log.levels.ERROR)
      vim.api.nvim_buf_delete(builder.buf_nr, { force = true })
      return
    end
    ---@cast sess kubectl.DashboardSession

    sess:resize(win_width, win_height)

    -- Setup common keymaps
    local keymap_opts = { buffer = builder.buf_nr, noremap = true, silent = true }

    local function send_key(key)
      sess:write(vim.api.nvim_replace_termcodes(key, true, true, true))
      vim.defer_fn(function()
        local frame = sess:read_frame()
        if frame then
          apply_frame(builder.buf_nr, frame)
        end
      end, 10)
    end

    for _, key in ipairs({ "<Tab>", "<S-Tab>", "?" }) do
      vim.keymap.set("n", key, function()
        send_key(key)
      end, keymap_opts)
    end

    vim.keymap.set("n", "K", function()
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
      sess:write(string.format("\x00CURSOR:%d\x00", cursor_line))
      send_key("K")
    end, keymap_opts)

    vim.keymap.set("n", "r", function()
      send_key("r")
    end, keymap_opts)

    vim.keymap.set("n", "f", function()
      send_key("f")
    end, keymap_opts)

    vim.keymap.set("n", "q", function()
      sess:write("q")
      sess:close()
    end, keymap_opts)

    -- Create autocmd group
    local augroup = vim.api.nvim_create_augroup("KubectlDashboard_" .. builder.buf_nr, { clear = true })

    -- Handle resize
    vim.api.nvim_create_autocmd("WinResized", {
      group = augroup,
      callback = function()
        if vim.api.nvim_win_is_valid(builder.win_nr) then
          sess:resize(vim.api.nvim_win_get_width(builder.win_nr), vim.api.nvim_win_get_height(builder.win_nr))
        end
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

function M.top()
  return create_dashboard({
    view_name = "top",
    title = "K8s Top",
    ft = "k8s_top",
    enable_folding = true,
  })
end

function M.overview()
  return create_dashboard({
    view_name = "overview",
    title = "K8s Overview",
    ft = "k8s_overview",
    enable_folding = true,
  })
end

-- Backwards compatibility
M.open = function(view_name, title)
  return create_dashboard({
    view_name = view_name,
    title = title or "dashboard",
    ft = "k8s_" .. view_name,
    enable_folding = true,
  })
end

return M
