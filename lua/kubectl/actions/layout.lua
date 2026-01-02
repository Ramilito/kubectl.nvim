local config = require("kubectl.config")
local M = {}
local api = vim.api

--- Set buffer options.
--- @param win integer: The window number.
function M.set_win_options(win)
  api.nvim_set_option_value("cursorline", true, { win = win })
  api.nvim_set_option_value("wrap", false, { win = win })
  api.nvim_set_option_value("sidescrolloff", 0, { scope = "local", win = win })
end

--- Set buffer options.
--- @param buf integer: The buffer number.
--- @param filetype string: The filetype for the buffer.
--- @param syntax string: The syntax for the buffer.
--- @param bufname string: The name of the buffer.
function M.set_buf_options(buf, filetype, syntax, bufname)
  api.nvim_set_option_value("filetype", filetype, { buf = buf })
  api.nvim_set_option_value("syntax", syntax, { buf = buf })
  api.nvim_set_option_value("bufhidden", "hide", { scope = "local" })
  api.nvim_set_option_value("modified", false, { buf = buf })
  api.nvim_buf_set_var(buf, "buf_name", bufname)

  -- TODO: How do we handle long text?
  -- api.nvim_set_option_value("wrap", true, { scope = "local" })
  -- api.nvim_set_option_value("linebreak", true, { scope = "local" })

  -- TODO: Is this neaded?
  -- vim.wo[win].winhighlight = "Normal:Normal"
  -- TODO: Need to workout how to reuse single buffer with this setting, or not
  -- api.nvim_set_option_value("modifiable", false, { buf = buf })
end

--- Get the main layout window.
--- @return integer: The current window number.
function M.main_layout()
  -- TODO: Should we create a new win?
  return api.nvim_get_current_win()
end

--- Create a float dynamic layout.
--- @param buf integer: The buffer number.
--- @param filetype string: The filetype for the buffer.
--- @param title string|nil: The title for the buffer (optional).
--- @param opts { relative: string|nil, enter: boolean? }|nil: The options for the float layout (optional).
--- @return integer: The window number.
function M.float_dynamic_layout(buf, filetype, title, opts)
  opts = opts or {}
  local enter = opts.enter ~= false -- default to true unless explicitly false
  local relative = opts.relative or "editor"
  if filetype ~= "" then
    title = filetype .. " - " .. (title or "")
  end

  local width, height = M.get_editor_dimensions()
  local win_width, win_height = 100, 15 -- Define the floating window size
  local win = api.nvim_open_win(buf, enter, {
    relative = relative,
    style = "minimal",
    width = 100,
    height = 5,
    col = (width - win_width) * 0.5,
    row = (height - win_height) * 0.5,
    border = "rounded",
    title = title,
  })

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(
      _, -- use nil as first argument (since it is buffer handle)
      buf_nr, -- buffer number
      _, -- buffer changedtick
      _, -- first line number of the change (0-indexed)
      lastline, -- last line number of the change
      new_lastline -- last line number after the change
    )
      if lastline ~= new_lastline then
        M.win_size_fit_content(buf_nr, win, 2)
      end
    end,
  })

  return win
end

--- Create a float layout.
--- @param buf integer: The buffer number.
--- @param filetype string: The filetype for the buffer.
--- @param title string|nil: The title for the buffer (optional).
-- luacheck: no max line length
--- @param opts { relative: string|nil, size: { width: number|nil, height: number|nil, row: number|nil,col: number|nil }}|nil: The options for the float layout (optional).
--- @return integer: The window number.
function M.float_layout(buf, filetype, title, opts)
  opts = opts or {}
  local size = opts.size or {}
  if filetype ~= "" then
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

---@class FramedPaneConfig
---@field title string|nil Window title
---@field width number|nil Width ratio (0-1) for multi-pane layouts, defaults to equal split

---@class FramedLayoutConfig
---@field title string|nil Main title for the frame (shown on hints bar)
---@field panes FramedPaneConfig[] Pane configurations (1 or more)
---@field width number|nil Overall width ratio (default 0.8)
---@field height number|nil Overall height ratio (default 0.8)

---@class FramedWindowResult
---@field hints_win number Hints window
---@field pane_wins number[] Array of pane window handles
---@field dimensions { total_width: number, total_height: number, content_height: number }

--- Create framed float windows with hints bar at top and content pane(s) below.
--- This function only creates windows - buffer creation is handled by buffers.lua
--- @param bufs { hints_buf: number, pane_bufs: number[] } Buffers to attach to windows
--- @param opts FramedLayoutConfig
--- @return FramedWindowResult
function M.float_framed_windows(bufs, opts)
  local width_ratio = opts.width or 0.8
  local height_ratio = opts.height or 0.8

  local editor_width, editor_height = M.get_editor_dimensions()
  local total_width = math.floor(editor_width * width_ratio)
  local total_height = math.floor(editor_height * height_ratio)
  local col = math.floor((editor_width - total_width) / 2)
  local row = math.floor((editor_height - total_height) / 2)

  -- Hints bar: 1 line of content
  local hints_height = 1
  local content_height = total_height - hints_height - 2 -- subtract hints + border gap

  -- Create hints window
  local hints_win = api.nvim_open_win(bufs.hints_buf, false, {
    relative = "editor",
    width = total_width,
    height = hints_height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    focusable = false,
  })

  -- Create content pane windows
  local pane_wins = {}
  local num_panes = #opts.panes
  local pane_col = col
  local content_row = row + hints_height + 2

  for i, pane_config in ipairs(opts.panes) do
    local pane_width
    if num_panes == 1 then
      pane_width = total_width
    else
      local width_frac = pane_config.width or (1 / num_panes)
      pane_width = math.floor(total_width * width_frac)
      if i == num_panes then
        pane_width = total_width - (pane_col - col)
      end
    end

    local is_first = i == 1
    local pane_win = api.nvim_open_win(bufs.pane_bufs[i], is_first, {
      relative = "editor",
      width = pane_width,
      height = content_height,
      col = pane_col,
      row = content_row,
      style = "minimal",
      border = "rounded",
      title = pane_config.title and (" " .. pane_config.title .. " ") or nil,
      title_pos = "center",
    })

    if is_first then
      api.nvim_set_option_value("cursorline", true, { win = pane_win })
    end

    table.insert(pane_wins, pane_win)
    pane_col = pane_col + pane_width + 1
  end

  return {
    hints_win = hints_win,
    pane_wins = pane_wins,
    dimensions = {
      total_width = total_width,
      total_height = total_height,
      content_height = content_height,
    },
  }
end

--- Fits content to window size
--- @param buf_nr integer: The buffer number.
--- @param height_offset integer: The height offset.
--- @param min_width integer|nil: The minimum width.
--- @return { height: number, width: number }
function M.win_size_fit_content(buf_nr, win_nr, height_offset, min_width)
  if not vim.api.nvim_win_is_valid(win_nr) then
    win_nr = vim.api.nvim_get_current_win()
  end
  local win_config = vim.api.nvim_win_get_config(win_nr)

  local rows = vim.api.nvim_buf_line_count(buf_nr)
  -- Calculate the maximum width (number of columns of the widest line)
  local max_columns = 100
  local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, rows, false)

  for _, line in ipairs(lines) do
    local line_width = vim.api.nvim_strwidth(line)
    if line_width > max_columns then
      max_columns = line_width
    end
  end

  win_config.height = rows + height_offset
  win_config.width = math.max(max_columns, min_width or 0)

  api.nvim_set_option_value("scrolloff", rows + height_offset, { win = win_nr })
  vim.api.nvim_win_set_config(win_nr, win_config)
  return win_config
end

return M
