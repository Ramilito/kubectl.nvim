local hl = require("kubectl.view.highlight")
local layout = require("kubectl.view.layout")
local api = vim.api
local M = {}

function M.filter_buffer(content, filetype, opts)
  local bufname = "kubectl_filter"

  local buf = vim.fn.bufnr(bufname)

  if buf == -1 then
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, bufname)
    api.nvim_buf_set_option(buf, "buftype", "prompt")
  end
  local win = layout.filter_layout(buf, filetype, opts.title or "")

  api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
  vim.api.nvim_buf_set_lines(buf, #opts.hints, -1, false, { content .. FILTER })

  vim.fn.prompt_setcallback(buf, function(input)
    if not input then
      FILTER = nil
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
  local bufname = opts.title or ""
  if bufname == "" then
    bufname = "kubectl_float"
  end

  local buf = vim.fn.bufnr(bufname)

  if buf == -1 then
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, bufname)
  end

  if opts.hints and #opts.hints > 1 then
    api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
    api.nvim_buf_set_lines(buf, #opts.hints, -1, false, content)
  else
    api.nvim_buf_set_lines(buf, 0, -1, false, content)
  end

  local win = layout.float_layout(buf, filetype, opts.title or "")
  vim.bo[buf].buflisted = false
  vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype)
  hl.set_highlighting(buf)
end

function M.buffer(content, filetype, opts)
  local bufname = opts.title or ""
  local buf = vim.fn.bufnr(bufname)

  if buf == -1 then
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, bufname)
  end

  if opts.hints and #opts.hints > 1 then
    api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
    api.nvim_buf_set_lines(buf, #opts.hints, -1, false, content)
  else
    api.nvim_buf_set_lines(buf, 0, -1, false, content)
  end

  api.nvim_set_current_buf(buf)
  local win = layout.main_layout()

  layout.set_buf_options(buf, win, filetype, filetype)
  hl.set_highlighting(buf)
end

return M
