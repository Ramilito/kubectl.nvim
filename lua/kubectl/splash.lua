-- lua/kubectl/splash.lua
---@class KubectlSplash
---@field show fun(opts?: {status?: string, autohide?: boolean, timeout?: integer, title?: string, tips?: string[]})
---@field status fun(text: string)
---@field done fun(msg?: string)
---@field fail fun(msg?: string)
---@field hide fun()
---@field is_open fun(): boolean

local Splash = {}

local uv  = vim.uv or vim.loop
local api = vim.api
local fn  = vim.fn

local ns = api.nvim_create_namespace("kubectl_splash")

local state = {
  bufnr        = nil,
  winid        = nil,
  spin_timer   = nil,
  tip_timer    = nil,
  guard_timer  = nil,
  spinner_idx  = 1,
  spin_base    = "Loading Kubernetes context…",
  status_lnum  = nil, -- 0-based
  tip_lnum     = nil, -- 0-based
}

local spinner = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" }
local default_tips = {
  "Use :Kubectl ns <name> to pin a namespace",
  "Press ? in the view for keymaps",
  "g? toggles wide table columns",
  "Hint: kubectl -n kube-system get pods",
  "Press r to refresh resources",
}

local k8s_logo = {
  "      __  __     _        _ _ ",
  "     |  \\/  |___| |_ _  _| | |",
  "     | |\\/| / -_)  _| || | | |",
  "     |_|  |_\\___|\\__|\\_,_|_|_|",
}

-- ---------- utils ----------

local function is_open()
  return state.bufnr and api.nvim_buf_is_valid(state.bufnr)
     and state.winid and api.nvim_win_is_valid(state.winid)
end

local function stop_timer(name)
  local t = state[name]
  if t then
    pcall(t.stop, t)
    pcall(t.close, t)
    state[name] = nil
  end
end

local function display_width(s)
  -- Handles wide glyphs (spinner/emoji)
  return fn.strdisplaywidth(s)
end

local function center_line(s, width)
  local w = math.max(0, width or 0)
  local dw = display_width(s)
  local pad = math.max(0, math.floor((w - dw) / 2))
  return string.rep(" ", pad) .. s
end

local function center_lines(lines, width)
  local out = {}
  for _, l in ipairs(lines) do
    table.insert(out, center_line(l, width))
  end
  return out
end

local function set_status(text, hl)
  if not is_open() then return end
  local ok, win_w = pcall(api.nvim_win_get_width, state.winid)
  if not ok then return end
  local centered = center_line(text, win_w - 2)
  -- clear old highlights on that line before writing
  api.nvim_buf_clear_namespace(state.bufnr, ns, state.status_lnum, state.status_lnum + 1)
  api.nvim_buf_set_lines(state.bufnr, state.status_lnum, state.status_lnum + 1, false, { centered })
  api.nvim_buf_add_highlight(state.bufnr, ns, hl or "KubectlSplashTitle", state.status_lnum, 0, -1)
end

local function set_tip(text)
  if not is_open() then return end
  local ok, win_w = pcall(api.nvim_win_get_width, state.winid)
  if not ok then return end
  local centered = center_line("💡 " .. text, win_w - 2)
  api.nvim_buf_clear_namespace(state.bufnr, ns, state.tip_lnum, state.tip_lnum + 1)
  api.nvim_buf_set_lines(state.bufnr, state.tip_lnum, state.tip_lnum + 1, false, { centered })
  api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashMuted", state.tip_lnum, 0, -1)
end

local function start_spinner(base)
  stop_timer("spin_timer")
  if base and base ~= "" then state.spin_base = base end
  state.spin_timer = uv.new_timer()
  state.spin_timer:start(0, 80, function()
    vim.schedule(function()
      if not is_open() then
        stop_timer("spin_timer")
        return
      end
      state.spinner_idx = (state.spinner_idx % #spinner) + 1
      set_status(string.format("%s  %s", spinner[state.spinner_idx], state.spin_base))
    end)
  end)
end

local function start_tips(tips)
  stop_timer("tip_timer")
  tips = (type(tips) == "table" and #tips > 0) and tips or default_tips
  local idx = math.random(#tips)
  set_tip(tips[idx])
  state.tip_timer = uv.new_timer()
  state.tip_timer:start(2500, 2500, function()
    idx = (idx % #tips) + 1
    vim.schedule(function()
      set_tip(tips[idx])
    end)
  end)
end

local function close_window()
  stop_timer("spin_timer")
  stop_timer("tip_timer")
  stop_timer("guard_timer")

  if state.winid and api.nvim_win_is_valid(state.winid) then
    pcall(api.nvim_win_close, state.winid, true)
  end
  if state.bufnr and api.nvim_buf_is_valid(state.bufnr) then
    pcall(api.nvim_buf_delete, state.bufnr, { force = true })
  end
  state.bufnr, state.winid = nil, nil
  state.status_lnum, state.tip_lnum = nil, nil
end

local function create_window(opts)
  if is_open() then return end

  local columns = vim.o.columns
  local lines   = vim.o.lines - vim.o.cmdheight
  local win_w   = math.min(64, math.max(48, math.floor(columns * 0.5)))
  local win_h   = 12

  local row = math.floor((lines - win_h) / 2 - 1)
  local col = math.floor((columns - win_w) / 2)

  state.bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(state.bufnr, "bufhidden", "wipe")
  api.nvim_buf_set_name(state.bufnr, "kubectl://splash")
  -- Optional filetype for user custom highlights
  pcall(api.nvim_buf_set_option, state.bufnr, "filetype", "kubectl_splash")

  state.winid = api.nvim_open_win(state.bufnr, false, {
    relative   = "editor",
    width      = win_w,
    height     = win_h,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. (opts.title or "kubectl.nvim") .. " ",
    title_pos  = "center",
    noautocmd  = true,
  })

  -- highlight groups (default links keep user themes intact)
  api.nvim_set_hl(0, "KubectlSplashTitle",   { link = "Title",            default = true })
  api.nvim_set_hl(0, "KubectlSplashMuted",   { link = "Comment",          default = true })
  api.nvim_set_hl(0, "KubectlSplashAccent",  { link = "Constant",         default = true })
  api.nvim_set_hl(0, "KubectlSplashSuccess", { link = "DiagnosticOk",     default = true })  -- fallback if theme lacks: DiagnosticOk
  api.nvim_set_hl(0, "KubectlSplashError",   { link = "DiagnosticError",  default = true })

  -- content
  local header = center_lines(k8s_logo, win_w - 2)
  local lines_tbl = { "" }                 -- top padding (line 0)
  vim.list_extend(lines_tbl, header)       -- lines 1..#header
  table.insert(lines_tbl, "")              -- post-header pad
  table.insert(lines_tbl, "")              -- status line (will be filled)
  table.insert(lines_tbl, "")              -- tip line (will be filled)

  api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines_tbl)

  -- compute line numbers
  local top_pad = 1
  local header_h = #header
  state.status_lnum = top_pad + header_h + 1   -- after one blank pad (0-based)
  state.tip_lnum    = state.status_lnum + 1

  -- accent the whole logo block
  for i = 0, header_h - 1 do
    api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashAccent", top_pad + i, 0, -1)
  end

  -- always allow 'q' to close
  vim.keymap.set("n", "q", function() Splash.hide() end,
    { buffer = state.bufnr, nowait = true, noremap = true, silent = true })
end

-- ---------- public API ----------

--- Show splash while work is in progress.
--- @param opts? { status?: string, autohide?: boolean, timeout?: integer, tips?: string[], title?: string }
function Splash.show(opts)
  opts = opts or {}
  local timeout = type(opts.timeout) == "number" and opts.timeout or 30000

  vim.schedule(function()
    create_window(opts)
    start_spinner(opts.status or state.spin_base)
    start_tips(opts.tips)

    -- cancelable autohide guard
    stop_timer("guard_timer")
    if opts.autohide ~= false then
      state.guard_timer = uv.new_timer()
      state.guard_timer:start(timeout, 0, function()
        vim.schedule(function()
          if is_open() then
            Splash.fail("Timed out. Press q to close.")
          end
        end)
        stop_timer("guard_timer")
      end)
    end
  end)
end

--- Update the base status (spinner keeps animating with this text).
function Splash.status(text)
  if not text or text == "" then return end
  -- Update the base used by the spinner and immediately reflect once.
  vim.schedule(function()
    if not is_open() then return end
    state.spin_base = text
    set_status(string.format("%s  %s", spinner[state.spinner_idx], state.spin_base))
  end)
end

local function finalize(kind, msg, delay_ms)
  vim.schedule(function()
    if not is_open() then return end
    -- Stop timers first so our message is not overwritten by the spinner.
    stop_timer("spin_timer")
    stop_timer("tip_timer")
    stop_timer("guard_timer")

    local prefix = (kind == "ok") and "✔  " or "✖  "
    local hl     = (kind == "ok") and "KubectlSplashSuccess" or "KubectlSplashError"
    local text   = prefix .. (msg and tostring(msg) or ((kind == "ok") and "Ready" or "Something went wrong"))
    set_status(text, hl)

    -- Close after a short delay so users can read the result.
    local t = uv.new_timer()
    t:start(delay_ms, 0, function()
      vim.schedule(close_window)
      pcall(t.stop, t); pcall(t.close, t)
    end)
  end)
end

--- Finish successfully (plays a short success flash, then closes).
function Splash.done(msg)
  finalize("ok", msg, 400)
end

--- Finish with error (shows message & leaves window a bit longer).
function Splash.fail(msg)
  finalize("err", msg, 1600)
end

--- Hide immediately.
function Splash.hide()
  vim.schedule(close_window)
end

--- Is the splash currently open?
function Splash.is_open()
  return is_open()
end

return Splash
