local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local layout = require("kubectl.actions.layout")
local state = require("kubectl.state")
local api = vim.api
local M = {}

--- Creates a buffer with a given name and type.
--- @param bufname string: The name of the buffer.
--- @param buftype string|nil: The type of the buffer (optional).
--- @return integer: The buffer number.
local function create_buffer(bufname, buftype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, bufname)
  if buftype then
    vim.api.nvim_set_option_value("buftype", buftype, { buf = buf })
  end
  return buf
end

--- Sets the lines in a buffer.
--- @param buf integer: The buffer number.
--- @param header table|nil: The header lines (optional).
--- @param content table: The content lines.
local function set_buffer_lines(buf, header, content)
  if header and #header >= 1 then
    vim.api.nvim_buf_set_lines(buf, 0, #header, false, header)
    vim.api.nvim_buf_set_lines(buf, #header, -1, false, content)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  end
end

--- Applies marks to a buffer.
--- @param bufnr integer: The buffer number.
--- @param marks table|nil: The marks to apply (optional).
--- @param header table|nil: The header data (optional).
function M.apply_marks(bufnr, marks, header)
  local ns_id = api.nvim_create_namespace("__kubectl_views")
  api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  state.marks.ns_id = ns_id

  vim.schedule(function()
    if header and header.marks then
      for _, mark in ipairs(header.marks) do
        local _, _ = pcall(api.nvim_buf_set_extmark, bufnr, ns_id, mark.row, mark.start_col, {
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
          hl_group = mark.hl_group or nil,
          virt_text = mark.virt_text or nil,
          virt_text_pos = mark.virt_text_pos or nil,
        })
        if mark.row == 0 and ok then
          state.content_row_start = start_row + 1
          table.insert(state.marks.header, result)
        end
      end
    end
  end)
end

--- Creates a filter buffer.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil, header: { data: table }, suggestions: table}: Options for the buffer.
function M.aliases_buffer(filetype, callback, opts)
  local bufname = "kubectl_filter"
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname, "prompt")
    vim.keymap.set("n", "q", function()
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.close()
    end, { buffer = buf, silent = true })
  end

  local win = layout.filter_layout(buf, filetype, opts.title or "")

  vim.fn.prompt_setcallback(buf, function(input)
    callback(input)
    vim.cmd("stopinsert")
    api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.close()
    -- vim.api.nvim_input("gr")
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, win, filetype, "", bufname)
  -- vim.fn.prompt_setprompt(buf, "Search: ")
  return buf
end

--- Creates a filter buffer.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil, header: { data: table }}: Options for the buffer.
function M.filter_buffer(filetype, opts)
  local bufname = "kubectl_filter"
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname, "prompt")
    vim.keymap.set("n", "q", function()
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.close()
    end, { buffer = buf, silent = true })
  end

  local win = layout.filter_layout(buf, filetype, opts.title or "")

  vim.fn.prompt_setcallback(buf, function(input)
    if not input then
      state.setFilter("")
    else
      state.setFilter(input)
    end

    api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.close()
    vim.api.nvim_input("gr")
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, win, filetype, "", bufname)
  return buf
end

--- Creates a confirmation buffer.
--- @param prompt string: The prompt to display.
--- @param filetype string: The filetype of the buffer.
--- @param onConfirm function: The function to call on confirmation.
--- @param opts { syntax: string|nil, content: table|nil, marks: table|nil, width: number|nil }|nil: Options for the buffer.
function M.confirmation_buffer(prompt, filetype, onConfirm, opts)
  opts = opts or {}
  local bufname = "kubectl_confirmation"
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname)
  end
  local content = opts.content or { "[y]es [n]o" }

  local layout_opts = {
    size = {
      width = math.max(#prompt + #filetype + 4, opts.width or 0),
      height = #content + 1,
      col = (vim.api.nvim_win_get_width(0) - #prompt + 2) * 0.5,
      row = (vim.api.nvim_win_get_height(0) - #content + 1) * 0.5,
    },
    relative = "win",
    header = {},
  }

  set_buffer_lines(buf, layout_opts.header.data, content)
  local win = layout.float_layout(buf, filetype, prompt, layout_opts)

  vim.api.nvim_buf_set_keymap(buf, "n", "y", "", {
    noremap = true,
    silent = true,
    callback = function()
      onConfirm(true)
      vim.api.nvim_win_close(win, true)
    end,
  })
  vim.api.nvim_buf_set_keymap(buf, "n", "n", "", {
    noremap = true,
    silent = true,
    callback = function()
      onConfirm(false)
      vim.api.nvim_win_close(win, true)
    end,
  })
  vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype, bufname)
  M.apply_marks(buf, opts.marks, nil)
end

--- Creates a floating buffer.
--- @param content table: The content lines.
--- @param marks table: The marks to apply.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil, syntax: string|nil, header: { data: table }}: Options for the buffer.
--- @return integer: The buffer number.
function M.floating_buffer(content, marks, filetype, opts)
  local bufname = opts.title or "kubectl_float"
  opts.header = opts.header or {}
  local buf = vim.fn.bufnr(bufname, false)

  if buf == -1 then
    buf = create_buffer(bufname)
  end

  set_buffer_lines(buf, opts.header.data, content)

  local win = layout.float_layout(buf, filetype, opts.title or "")
  vim.keymap.set("n", "q", function()
    vim.cmd("bdelete")
  end, { buffer = buf, silent = true })

  layout.set_buf_options(buf, win, filetype, opts.syntax or filetype, bufname)
  M.apply_marks(buf, marks, opts.header)

  return buf
end

--- Creates or updates a buffer.
--- @param content table: The content lines.
--- @param marks table: The marks to apply.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil, header: { data: table }}: Options for the buffer.
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
  M.apply_marks(buf, marks, opts.header)
end

--- Creates or updates a notification buffer.
--- @param opts { width: integer|nil, close: boolean|nil, append: boolean|nil }: Options for the buffer.
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
  vim.api.nvim_set_option_value("winblend", config.options.notifications.blend, { win = win })

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
