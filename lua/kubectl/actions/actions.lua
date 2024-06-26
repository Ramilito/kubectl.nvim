local hl = require("kubectl.actions.highlight")
local layout = require("kubectl.actions.layout")
local state = require("kubectl.state")
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
  hl.set_highlighting(win)
end

function M.confirmation_buffer(prompt, filetype, onConfirm)
  local bufname = "kubectl_confirmation"
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname)
  end
  local content = { "[y]es [n]o" }

  local opts = {
    size = {
      width = #prompt + 4,
      height = #content + 1,
      col = (vim.api.nvim_win_get_width(0) - #prompt + 2) * 0.5,
      row = (vim.api.nvim_win_get_height(0) - #content + 1) * 0.5,
    },
    relative = "win",
  }

  set_buffer_lines(buf, opts.hints, content)
  local win = layout.float_layout(buf, filetype, prompt, opts)

  vim.api.nvim_buf_set_keymap(buf, "n", "y", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
      onConfirm(true)
    end,
  })
  vim.api.nvim_buf_set_keymap(buf, "n", "n", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
      onConfirm(false)
    end,
  })
  vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype)
  hl.setup()
  hl.set_highlighting(win)
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
  hl.set_highlighting(win)
end

function M.buffer(content, filetype, opts)
  local bufname = opts.title or "kubectl"
  local buf = vim.fn.bufnr(bufname, false)

  local win = layout.main_layout()
  if buf == -1 then
    buf = create_buffer(bufname)
    layout.set_buf_options(buf, win, filetype, filetype)
  end

  set_buffer_lines(buf, opts.hints, content)

  api.nvim_set_current_buf(buf)
  hl.set_highlighting(win)
end

function M.notification_buffer(content, close)
  local bufname = "notification"
  local buf = vim.fn.bufnr(bufname, false)

  if close then
    vim.api.nvim_buf_delete(buf, { force = true })
    return
  end

  if buf == -1 then
    buf = create_buffer(bufname)
  end
  set_buffer_lines(buf, {}, content)

  local width = 0
  for _, value in ipairs(content) do
    if #value > width then
      width = #value
    end
  end

  local win = layout.notification_laout(buf, bufname, { width = width })

  layout.set_buf_options(buf, win, bufname, bufname)

  api.nvim_set_option_value("cursorline", false, { win = win })
  api.nvim_set_option_value("winblend", 100, { win = win })
  hl.setup(win)
  hl.set_highlighting(win)
end

return M
