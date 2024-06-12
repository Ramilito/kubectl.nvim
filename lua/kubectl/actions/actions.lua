local hl = require("kubectl.actions.highlight")
local layout = require("kubectl.actions.layout")
local state = require("kubectl.utils.state")
local api = vim.api
local M = {}

local function create_buffer(bufname, buftype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, bufname)
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
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname, "prompt")
    vim.keymap.set("n", "q", function()
      vim.bo.modified = false
      vim.cmd.close()
    end, { buffer = buf, silent = true })
  end

  local win = layout.filter_layout(buf, filetype, opts.title or "")

  api.nvim_buf_set_lines(buf, 0, #opts.hints, false, opts.hints)
  vim.api.nvim_buf_set_lines(buf, #opts.hints, -1, false, { content .. state.getFilter() })

  vim.fn.prompt_setcallback(buf, function(input)
    if not input then
      state.setFilter("")
    else
      state.setFilter(input)
    end
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_input("R")
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, win, filetype, "")
  hl.setup()
  hl.set_highlighting(buf)
end

function M.floating_buffer(content, filetype, opts)
  local bufname = opts.title or "kubectl_float"
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname)
  end

  set_buffer_lines(buf, opts.hints, content)

  local win = layout.float_layout(buf, filetype, opts.title or "")
  vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype)
  hl.setup()
  hl.set_highlighting(buf)
end

function M.buffer(content, filetype, opts)
  local bufname = opts.title or "kubectl"
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname)
    local win = layout.main_layout()
    layout.set_buf_options(buf, win, filetype, filetype)
  end

  set_buffer_lines(buf, opts.hints, content)

  api.nvim_set_current_buf(buf)
  hl.set_highlighting(buf)
end

return M
