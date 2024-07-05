local config = require("kubectl.config")
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

local function set_buffer_lines(buf, header, content)
  if header and #header > 1 then
    vim.api.nvim_buf_set_lines(buf, 0, #header, false, header)
    vim.api.nvim_buf_set_lines(buf, #header, -1, false, content)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  end
end

local function apply_marks(bufnr, marks, header)
  local ns_id = api.nvim_create_namespace("__kubectl_views")
  api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  state.marks.ns_id = ns_id

  vim.schedule(function()
    if header and header.marks then
      for _, mark in ipairs(header.marks) do
        local ok, result = pcall(api.nvim_buf_set_extmark, bufnr, ns_id, mark.row, mark.start_col, {
          end_line = mark.row,
          end_col = mark.end_col,
          hl_group = mark.hl_group,
          hl_eol = mark.hl_eol or nil,
          virt_text = mark.virt_text or nil,
          virt_text_pos = mark.virt_text_pos or nil,
        })
      end
    end
    if marks then
      state.marks.header = {}
      for _, mark in ipairs(marks) do
        local start_row = mark.row
        if header and header.data then
          start_row = start_row + #header.data
        end
        local ok, result = pcall(api.nvim_buf_set_extmark, bufnr, ns_id, start_row, mark.start_col, {
          end_line = start_row,
          end_col = mark.end_col,
          hl_group = mark.hl_group,
        })
        if mark.row == 0 then
          table.insert(state.marks.header, result)
        end
      end
    end
  end)
end

function M.filter_buffer(content, marks, filetype, opts)
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

  api.nvim_buf_set_lines(buf, 0, #opts.header.data, false, opts.header.data)
  vim.api.nvim_buf_set_lines(buf, #opts.header.data, -1, false, { content .. state.getFilter() })

  vim.fn.prompt_setcallback(buf, function(input)
    if not input then
      state.setFilter("")
    else
      state.setFilter(input)
    end

    vim.bo.modified = false
    vim.cmd.close()
    vim.api.nvim_input("R")
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, win, filetype, "", bufname)
  apply_marks(buf, marks, opts.header)
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
    header = {},
  }

  set_buffer_lines(buf, opts.header.data, content)
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

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype, bufname)
end

function M.floating_buffer(content, marks, filetype, opts)
  local bufname = opts.title or "kubectl_float"
  opts.header = opts.header or {}
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname)
  end

  set_buffer_lines(buf, opts.header.data, content)

  local win = layout.float_layout(buf, filetype, opts.title or "")
  vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype, bufname)
  apply_marks(buf, marks, opts.header)
end

function M.buffer(content, marks, filetype, opts)
  local bufname = opts.title or "kubectl"
  opts.header = opts.header or {}
  local buf = vim.fn.bufnr(bufname, false)
  local win = layout.main_layout()

  if buf == -1 then
    buf = create_buffer(bufname)
    layout.set_buf_options(buf, win, filetype, filetype, bufname)
  end

  set_buffer_lines(buf, opts.header.data, content)
  api.nvim_set_current_buf(buf)
  apply_marks(buf, marks, opts.header)
end

function M.notification_buffer(opts)
  opts.width = opts.width or 40
  local bufname = "notification"
  local marks = {}
  local buf = vim.fn.bufnr(bufname, false)

  if opts.close then
    local _, _ = pcall(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    return
  end

  if buf == -1 then
    buf = create_buffer(bufname)
  end

  if opts.append then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, line in ipairs(lines) do
      table.insert(state.notifications, #state.notifications, line)
    end
  end

  for index, line in ipairs(state.notifications) do
    table.insert(marks, { row = index - 1, start_col = 0, end_col = #line, hl_group = hl.symbols.gray })
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.notifications)
  local win = layout.notification_layout(buf, bufname, { width = opts.width, height = #state.notifications })
  vim.api.nvim_win_set_option(win, "winblend", config.options.notifications.blend)

  local ns_id = api.nvim_create_namespace("__kubectl_notifications")
  for _, mark in ipairs(marks) do
    pcall(api.nvim_buf_set_extmark, buf, ns_id, mark.row, mark.start_col, {
      end_line = mark.row,
      end_col = mark.end_col,
      hl_group = mark.hl_group,
    })
  end
end

return M
