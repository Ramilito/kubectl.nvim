local hl = require("kubectl.actions.highlight")
local layout = require("kubectl.actions.layout")
local api = vim.api
local M = {}

local function create_or_get_buffer(bufname, buftype)
  local buf = vim.fn.bufnr(bufname, true)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, bufname)
  end
  if buftype then
    vim.api.nvim_buf_set_option(buf, "buftype", buftype)
  end

  return buf
end

local function set_buffer_lines(buf, hints, content)
  if hints and #hints > 1 then
    vim.api.nvim_buf_set_lines(buf, 0, #hints, false, hints)
    vim.api.nvim_buf_set_lines(buf, #hints, -1, false, content)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  end
end

function M.filter_buffer(content, filetype, opts)
  local bufname = "kubectl_filter"
  local buf = create_or_get_buffer(bufname, "prompt")
  local win = layout.filter_layout(buf, filetype, opts.title or "")

  api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
  vim.api.nvim_buf_set_lines(buf, #opts.hints, -1, false, { content .. FILTER })

  vim.fn.prompt_setcallback(buf, function(input)
    if not input then
      FILTER = ""
    else
      FILTER = input
    end
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_input("R")
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, win, filetype, "")
  hl.set_highlighting(buf)
end

function M.floating_buffer(content, filetype, opts)
  local bufname = opts.title or "kubectl_float"

  local buf = create_or_get_buffer(bufname, "")
  set_buffer_lines(buf, opts.hints, content)

  local win = layout.float_layout(buf, filetype, opts.title or "")
  vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype)
  hl.set_highlighting(buf)
end

function M.buffer(content, filetype, opts)
  local bufname = opts.title or "kubectl"
  local buf = create_or_get_buffer(bufname)
  set_buffer_lines(buf, opts.hints, content)

  api.nvim_set_current_buf(buf)
  local win = layout.main_layout()

  layout.set_buf_options(buf, win, filetype, filetype)
  hl.set_highlighting(buf)
end

return M
