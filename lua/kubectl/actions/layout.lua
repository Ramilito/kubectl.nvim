local config = require("kubectl.config")
local M = {}
local api = vim.api

function M.set_buf_options(buf, win, filetype, syntax)
  api.nvim_set_option_value("filetype", filetype, { buf = buf })
  api.nvim_set_option_value("syntax", syntax, { buf = buf })
  api.nvim_set_option_value("bufhidden", "hide", { scope = "local" })
  api.nvim_set_option_value("cursorline", true, { win = win })
  api.nvim_set_option_value("modified", false, { buf = buf })

  -- TODO: How do we handle long text?
  -- api.nvim_set_option_value("wrap", true, { scope = "local" })
  -- api.nvim_set_option_value("linebreak", true, { scope = "local" })

  -- TODO: Is this neaded?
  -- vim.wo[win].winhighlight = "Normal:Normal"
  -- TODO: Need to workout how to reuse single buffer with this setting, or not
  -- api.nvim_set_option_value("modifiable", false, { buf = buf })
end

function M.main_layout()
  -- TODO: Should we create a new win?
  return api.nvim_get_current_win()
end

function M.filter_layout(buf, filetype, title)
  local width = 0.8 * vim.o.columns
  local height = 5
  local row = 10
  local col = 10

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    width = math.floor(width),
    height = math.floor(height),
    row = row,
    border = "rounded",
    col = col,
    title = filetype .. " - " .. (title or ""),
  })
  return win
end

function M.float_layout(buf, filetype, title, opts)
  opts = opts or {}
  local size = opts.size or {}
  if filetype then
    title = filetype .. " - " .. (title or "")
  end

  local win = api.nvim_open_win(buf, true, {
    relative = opts.relative or "editor",
    style = "minimal",
    width = size.width or math.floor(config.options.float_size.width * vim.o.columns),
    height = size.height or math.floor(config.options.float_size.height * vim.o.lines),
    row = size.row or config.options.float_size.row,
    col = size.col or config.options.float_size.col,
    border = "rounded",
    title = title,
  })
  return win
end

function M.notification_layout(buf, title, opts)
  local editor_width, editor_height = M.get_editor_dimensions()
  local height = math.min(2, editor_height)
  local width = math.min(opts.width, editor_width - 4) -- guess width of signcolumn etc.
  local row_max = vim.api.nvim_win_get_height(0)

  local col = vim.api.nvim_win_get_width(0)
  local win = api.nvim_open_win(buf, false, {
    relative = "win",
    style = "minimal",
    width = width,
    height = height,
    row = row_max - 2,
    col = col,
    focusable = false,
    border = "none",
    anchor = "SE",
    title = title,
    noautocmd = true,
    zindex = 45, -- Intentionally below standard float index
  })
  return win
end

--- Copied from: https://github.com/j-hui/fidget.nvim/blob/main/lua/fidget/notification/window.lua#L189
--- Get the current width and height of the editor window.
---
---@return number width
---@return number height
function M.get_editor_dimensions()
  local statusline_height = 0
  local laststatus = vim.opt.laststatus:get()
  if laststatus == 2 or laststatus == 3 or (laststatus == 1 and #vim.api.nvim_tabpage_list_wins(0) > 1) then
    statusline_height = 1
  end

  local height = vim.opt.lines:get() - (statusline_height + vim.opt.cmdheight:get())

  -- Does not account for &signcolumn or &foldcolumn, but there is no amazing way to get the
  -- actual "viewable" width of the editor
  --
  -- However, I cannot imagine that many people will render fidgets on the left side of their
  -- editor as it will more often overlay text
  local width = vim.opt.columns:get()

  return width, height
end

return M
