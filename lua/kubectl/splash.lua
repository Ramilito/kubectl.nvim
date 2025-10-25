-- lua/kubectl/splash.lua
local Splash = {}

local ns = vim.api.nvim_create_namespace("kubectl_splash")
local state = {
  bufnr = nil,
  winid = nil,
  timer = nil,
  tip_timer = nil,
  spinner_idx = 1,
}

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local tips = {
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

local function center_lines(lines, width)
  local out = {}
  for _, l in ipairs(lines) do
    local pad = math.max(0, math.floor((width - #l) / 2))
    table.insert(out, string.rep(" ", pad) .. l)
  end
  return out
end

local function create_window()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    return
  end

  -- size relative to editor
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local win_w = math.min(64, math.max(48, math.floor(columns * 0.5)))
  local win_h = 12

  local row = math.floor((lines - win_h) / 2 - 1)
  local col = math.floor((columns - win_w) / 2)

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(state.bufnr, "kubectl://splash")

  state.winid = vim.api.nvim_open_win(state.bufnr, false, {
    relative = "editor",
    width = win_w,
    height = win_h,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " kubectl.nvim ",
    title_pos = "center",
    noautocmd = true,
  })

  -- basic highlight groups (fallbacks if user theme lacks them)
  vim.api.nvim_set_hl(0, "KubectlSplashTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "KubectlSplashMuted", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "KubectlSplashAccent", { link = "Constant", default = true })

  -- fill content
  local header = center_lines(k8s_logo, win_w - 2)
  local lines = {
    "",
    unpack(header),
    "", -- logo block
    "", -- spinner + status goes here (we’ll update)
    "", -- tip
  }

  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashAccent", 2, 0, -1)
  vim.api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashAccent", 3, 0, -1)
  vim.api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashAccent", 4, 0, -1)
end

local function set_status(text)
  if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
    return
  end
  local w = vim.api.nvim_win_get_width(state.winid)
  local centered = center_lines({ text }, w - 2)[1]
  -- status line sits just after the logo block (line idx 6, 0-based)
  local line_idx = 6
  vim.api.nvim_buf_set_lines(state.bufnr, line_idx, line_idx + 1, false, { centered })
  vim.api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashTitle", line_idx, 0, -1)
end

local function set_tip(text)
  if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
    return
  end
  local w = vim.api.nvim_win_get_width(state.winid)
  local centered = center_lines({ "💡 " .. text }, w - 2)[1]
  local tip_idx = 8
  vim.api.nvim_buf_set_lines(state.bufnr, tip_idx, tip_idx + 1, false, { centered })
  vim.api.nvim_buf_add_highlight(state.bufnr, ns, "KubectlSplashMuted", tip_idx, 0, -1)
end

local function start_spinner(base)
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 80, function()
    vim.schedule(function()
      if not (state.winid and vim.api.nvim_win_is_valid(state.winid)) then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
        return
      end
      state.spinner_idx = (state.spinner_idx % #spinner) + 1
      set_status(string.format("%s  %s", spinner[state.spinner_idx], base))
    end)
  end)
end

local function start_tips()
  local idx = math.random(#tips)
  set_tip(tips[idx])
  state.tip_timer = vim.uv.new_timer()
  state.tip_timer:start(2500, 2500, function()
    idx = (idx % #tips) + 1
    vim.schedule(function()
      set_tip(tips[idx])
    end)
  end)
end

local function close_window()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.tip_timer then
    state.tip_timer:stop()
    state.tip_timer:close()
    state.tip_timer = nil
  end
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
  end
  state.bufnr, state.winid = nil, nil
end

-- Public API

--- Show splash while work is in progress.
-- @param opts table: { status?: string, autohide?: boolean }
function Splash.show(opts)
  opts = opts or {}
  create_window()
  start_spinner(opts.status or "Loading Kubernetes context…")
  start_tips()

  -- optional autohide guard if something hangs
  if opts.autohide ~= false then
    vim.defer_fn(function()
      -- If something went wrong and caller forgot to .done()
      if state.winid and vim.api.nvim_win_is_valid(state.winid) then
        Splash.fail("Timed out. Press q to close.")
        -- allow user to close with q
        vim.keymap.set("n", "q", function()
          Splash.done()
        end, { buffer = state.bufnr, nowait = true })
      end
    end, 30000) -- 30s
  end
end

--- Update the status line (keeps spinner).
function Splash.status(text)
  set_status(string.format("%s  %s", spinner[state.spinner_idx], text))
end

--- Finish successfully (plays a short success flash, then closes).
function Splash.done(msg)
  if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
    return
  end
  set_status((msg and ("✔  " .. msg)) or "✔  Ready")
  vim.defer_fn(function()
    close_window()
  end, 400)
end

--- Finish with error (shows message & leaves window a bit longer).
function Splash.fail(msg)
  if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
    return
  end
  set_status(("✖  %s"):format(msg or "Something went wrong"))
  vim.api.nvim_buf_add_highlight(state.bufnr, ns, "Error", 6, 0, -1)
  vim.defer_fn(function()
    close_window()
  end, 1600)
end

return Splash
