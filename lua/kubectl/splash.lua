local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")

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

local state = {
  bufnr = nil,
  winid = nil,
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
  "Press ? in the view for keymaps",
  "g? toggles wide table columns",
  "Hint: kubectl -n kube-system get pods",
  "Press r to refresh resources",
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
  return state.bufnr and api.nvim_buf_is_valid(state.bufnr) and state.winid and api.nvim_win_is_valid(state.winid)
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
  local ok, win_w = pcall(api.nvim_win_get_width, state.winid)
  if not ok then
    return
  end
  local centered = center_line(text, win_w - 2)
  -- clear old highlights on that line before writing
  api.nvim_buf_clear_namespace(state.bufnr, ns, state.status_lnum, state.status_lnum + 1)
  api.nvim_buf_set_lines(state.bufnr, state.status_lnum, state.status_lnum + 1, false, { centered })
  api.nvim_buf_add_highlight(state.bufnr, ns, symbol or hl.symbols.pending, state.status_lnum, 0, -1)
end

local function set_tip(text)
  if not is_open() then
    return
  end
  local ok, win_w = pcall(api.nvim_win_get_width, state.winid)
  if not ok then
    return
  end
  local centered = center_line("💡 " .. text, win_w - 2)
  api.nvim_buf_clear_namespace(state.bufnr, ns, state.tip_lnum, state.tip_lnum + 1)
  api.nvim_buf_set_lines(state.bufnr, state.tip_lnum, state.tip_lnum + 1, false, { centered })
  api.nvim_buf_add_highlight(state.bufnr, ns, hl.symbols.info, state.tip_lnum, 0, -1)
end

local function start_spinner(base)
  stop_timer("spin_timer")
  if base and base ~= "" then
    state.spin_base = base
  end
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

local function create_window()
  if is_open() then
    return
  end

  local builder = manager.get("splash")
  if not builder then
    return
  end

  builder.buf_nr, builder.win_nr = buffers.floating_dynamic_buffer(
    "k8s_splash",
    "kubectl_splash",
    function() end,
    { enter = false }
  )

  state.bufnr, state.winid = builder.buf_nr, builder.win_nr

  local header = center_lines(k8s_logo, 100 - 2)
  local lines_tbl = { "" }
  vim.list_extend(lines_tbl, header)
  table.insert(lines_tbl, "")
  table.insert(lines_tbl, "")
  table.insert(lines_tbl, "")

  api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines_tbl)

  local top_pad = 1
  local header_h = #header
  state.status_lnum = top_pad + header_h + 1 -- after one blank pad (0-based)
  state.tip_lnum = state.status_lnum + 1

  -- accent the whole logo block
  for i = 0, header_h - 1 do
    api.nvim_buf_add_highlight(state.bufnr, ns, hl.symbols.header, top_pad + i, 0, -1)
  end
end

--- @param opts? { status?: string, autohide?: boolean, timeout?: integer, tips?: string[], title?: string }
function Splash.show(opts)
  opts = opts or {}
  local timeout = type(opts.timeout) == "number" and opts.timeout or 30000

  manager.get_or_create("splash")
  vim.schedule(function()
    create_window()
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
    stop_timer("spin_timer")
    stop_timer("tip_timer")
    stop_timer("guard_timer")

    local prefix = (kind == "ok") and "✔  " or "✖  "
    local symbol = (kind == "ok") and hl.symbols.success or hl.symbols.error
    local text = prefix .. (msg and tostring(msg) or ((kind == "ok") and "Ready" or "Something went wrong"))
    set_status(text, symbol)

    -- Close after a short delay so users can read the result.
    local t = uv.new_timer()
    t:start(delay_ms, 0, function()
      vim.schedule(close_window)
      pcall(t.stop, t)
      pcall(t.close, t)
    end)
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
