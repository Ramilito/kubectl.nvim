local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")

---@class TimerHandle : userdata
---@field start fun(self: TimerHandle, timeout: integer, repeat_: integer, callback: fun())
---@field stop fun(self: TimerHandle)
---@field close fun(self: TimerHandle)

---@class KubectlSplash
---@field show fun(opts?: {status?: string, autohide?: boolean, timeout?: integer, title?: string, tips?: string[]})
---@field status fun(text: string)
---@field done fun(msg?: string)
---@field fail fun(msg?: string)
---@field hide fun()
---@field is_open fun(): boolean

local Splash = {}

local uv = vim.uv or vim.loop
local api = vim.api
local fn = vim.fn

local ns = api.nvim_create_namespace("kubectl_splash")

---@class SplashState
---@field spin_timer? TimerHandle
---@field tip_timer? TimerHandle
---@field guard_timer? TimerHandle
---@field spinner_idx integer
---@field spin_base string
---@field status_lnum? integer  -- 0-based
---@field tip_lnum? integer     -- 0-based
local state = {
  spin_timer = nil,
  tip_timer = nil,
  guard_timer = nil,
  spinner_idx = 1,
  spin_base = "Loading Kubernetes context…",
  status_lnum = nil, -- 0-based
  tip_lnum = nil, -- 0-based
}

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local default_tips = {
  "Use :Kubectl ns <name> to pin a namespace",
  "Press g? in the view for keymaps",
  "Hint: kubectl get pods",
  "Press gr to refresh resources",
}

local k8s_logo = {
  [[  _  __     _               _   _              _           ]],
  [[ | |/ /    | |             | | | |            (_)          ]],
  [[ | ' /_   _| |__   ___  ___| |_| |  _ ____   ___ _ __ ___   ]],
  [[ |  <| | | | '_ \ / _ \/ __| __| | | '_ \ \ / / | '_ ` _ \  ]],
  [[ | . \ |_| | |_) |  __/ (__| |_| |_| | | \ V /| | | | | | | ]],
  [[ |_|\_\__,_|_.__/ \___|\___|\__|_(_)_| |_|\_/ |_|_| |_| |_| ]],
}

local function is_open()
  local builder = manager.get("splash")
  if not builder then
    return false
  end
  return builder
    and builder.buf_nr
    and api.nvim_buf_is_valid(builder.buf_nr)
    and builder.win_id
    and api.nvim_win_is_valid(builder.win_id)
end

---@param t? TimerHandle
local function stop_timer(t)
  if t then
    pcall(t.stop, t)
    pcall(t.close, t)
  end
end

local function display_width(s)
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

local function set_status(text, symbol)
  if not is_open() then
    return
  end
  local builder = manager.get("splash")
  if not builder then
    return
  end
  local ok, win_config = pcall(vim.api.nvim_win_get_config, builder.win_id)
  if not ok or win_config.relative == "" then
    return
  end
  local centered = center_line(text, win_config.width - 2)
  -- clear old highlights on that line before writing
  api.nvim_buf_clear_namespace(builder.buf_nr, ns, state.status_lnum, state.status_lnum + 1)
  api.nvim_buf_set_lines(builder.buf_nr, state.status_lnum, state.status_lnum + 1, false, { centered })
  api.nvim_buf_set_extmark(builder.buf_nr, ns, state.status_lnum, 0, {
    end_row = state.status_lnum + 1,
    hl_group = symbol or hl.symbols.pending,
  })
end

local function set_tip(text)
  if not is_open() then
    return
  end
  local builder = manager.get("splash")
  if not builder then
    return
  end

  local ok, win_config = pcall(vim.api.nvim_win_get_config, builder.win_id)
  if not ok or win_config.relative == "" then
    return
  end
  local centered = center_line("💡 " .. text, win_config.width - 2)
  api.nvim_buf_clear_namespace(builder.buf_nr, ns, state.tip_lnum, state.tip_lnum + 1)
  api.nvim_buf_set_lines(builder.buf_nr, state.tip_lnum, state.tip_lnum + 1, false, { centered })
  api.nvim_buf_set_extmark(builder.buf_nr, ns, state.tip_lnum, 0, {
    end_row = state.tip_lnum + 1,
    hl_group = hl.symbols.info,
    hl_eol = true,
  })

  api.nvim_set_option_value("modified", false, { buf = builder.buf_nr })
end

local function start_spinner(base)
  stop_timer(state.spin_timer)
  if base and base ~= "" then
    state.spin_base = base
  end
  state.spin_timer = vim.uv.new_timer()
  state.spin_timer:start(0, 80, function()
    vim.schedule(function()
      if not is_open() then
        stop_timer(state.spin_timer)
        return
      end
      state.spinner_idx = (state.spinner_idx % #spinner) + 1
      set_status(string.format("%s  %s", spinner[state.spinner_idx], state.spin_base))
    end)
  end)
end

local function start_tips(tips)
  stop_timer(state.tip_timer)
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
  stop_timer(state.spin_timer)
  stop_timer(state.tip_timer)
  stop_timer(state.guard_timer)

  local builder = manager.get("splash")
  if not builder then
    return
  end
  if builder.win_id and api.nvim_win_is_valid(builder.win_id) then
    pcall(api.nvim_win_close, builder.win_id, true)
  end
  if builder.buf_nr and api.nvim_buf_is_valid(builder.buf_nr) then
    pcall(api.nvim_buf_delete, builder.buf_nr, { force = true })
  end
  state.status_lnum, state.tip_lnum = nil, nil
end

local function create_window()
  if is_open() then
    return
  end

  local builder = manager.get("splash")
  if not builder then
    return
  end

  builder.buf_nr, builder.win_nr = buffers.floating_dynamic_buffer("", "", function() end, { enter = false })

  pcall(vim.api.nvim_set_option_value, "winbar", "", { scope = "local", win = builder.win_nr })
  builder.buf_nr, builder.win_id = builder.buf_nr, builder.win_nr

  local header = center_lines(k8s_logo, 100 - 2)
  local lines_tbl = { "" }
  vim.list_extend(lines_tbl, header)
  table.insert(lines_tbl, "")
  table.insert(lines_tbl, "")
  table.insert(lines_tbl, "")

  pcall(api.nvim_buf_set_lines, builder.buf_nr, 0, -1, false, lines_tbl)

  local top_pad = 1
  local header_h = #header
  state.status_lnum = top_pad + header_h + 1 -- after one blank pad (0-based)
  state.tip_lnum = state.status_lnum + 1

  -- accent the whole logo block
  for i = 0, header_h - 1 do
    pcall(
      api.nvim_buf_set_extmark,
      builder.buf_nr,
      ns,
      top_pad + i,
      0,
      { end_row = top_pad + i + 1, hl_group = hl.symbols.header }
    )
  end
end

--- @param opts? { status?: string, autohide?: boolean, timeout?: integer, tips?: string[], title?: string }
function Splash.show(opts)
  if is_open() then
    return
  end
  opts = opts or {}
  local timeout = type(opts.timeout) == "number" and opts.timeout or 30000

  manager.get_or_create("splash")
  vim.schedule(function()
    create_window()
    start_spinner(opts.status or state.spin_base)
    start_tips(opts.tips)

    -- cancelable autohide guard
    stop_timer(state.guard_timer)
    if opts.autohide ~= false then
      state.guard_timer = uv.new_timer()
      state.guard_timer:start(timeout, 0, function()
        vim.schedule(function()
          if is_open() then
            Splash.fail("Timed out. Press q to close.")
          end
        end)
        stop_timer(state.guard_timer)
      end)
    end
  end)
end

function Splash.status(text)
  if not text or text == "" then
    return
  end
  -- Update the base used by the spinner and immediately reflect once.
  vim.schedule(function()
    if not is_open() then
      return
    end
    state.spin_base = text
    set_status(string.format("%s  %s", spinner[state.spinner_idx], state.spin_base))
  end)
end

local function finalize(kind, msg, delay_ms)
  vim.schedule(function()
    if not is_open() then
      return
    end
    -- Stop timers first so our message is not overwritten by the spinner.
    stop_timer(state.spin_timer)
    stop_timer(state.tip_timer)
    stop_timer(state.guard_timer)

    local prefix = (kind == "ok") and "✔  " or "✖  "
    local symbol = (kind == "ok") and hl.symbols.success or hl.symbols.error
    local text = prefix .. (msg and tostring(msg) or ((kind == "ok") and "Ready" or "Something went wrong"))
    set_status(text, symbol)

    -- Close after a short delay so users can read the result.
    local t = uv.new_timer()
    if t then
      t:start(delay_ms, 0, function()
        vim.schedule(close_window)
        pcall(t.stop, t)
        pcall(t.close, t)
      end)
    end
  end)
end

function Splash.done(msg)
  finalize("ok", msg, 400)
end

function Splash.fail(msg)
  finalize("err", msg, 2600)
end

function Splash.hide()
  vim.schedule(close_window)
end

function Splash.is_open()
  return is_open()
end

return Splash
