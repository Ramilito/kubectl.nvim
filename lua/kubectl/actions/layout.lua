local config = require("kubectl.config")
local M = {}
local api = vim.api

function M.set_buf_options(buf, win, filetype, syntax)
  api.nvim_set_option_value("filetype", filetype, { buf = buf })
  api.nvim_set_option_value("syntax", syntax, { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
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
  local win = api.nvim_get_current_win()
  return win
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
  -- title = filetype .. " - " .. (title or "")

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

return M
