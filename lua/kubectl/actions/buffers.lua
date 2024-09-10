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

local function get_buffer_by_name(bufname)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    local filename = vim.fs.basename(name)
    if filename == bufname then
      return buf
    end
  end
  return nil
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

  if header and header.marks then
    for _, mark in ipairs(header.marks) do
      local _, _ = api.nvim_buf_set_extmark(bufnr, ns_id, mark.row, mark.start_col, {
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
      -- adjust for content not being at first row
      local start_row = mark.row
      if header and header.data then
        start_row = start_row + #header.data
      end
      local result = api.nvim_buf_set_extmark(bufnr, ns_id, start_row, mark.start_col, {
        end_line = start_row,
        end_col = mark.end_col,
        hl_eol = mark.hl_eol or nil,
        hl_group = mark.hl_group or nil,
        hl_mode = mark.hl_mode or nil,
        virt_text = mark.virt_text or nil,
        virt_text_pos = mark.virt_text_pos or nil,
      })
      -- the first row is always column headers, we save that so other content can use it
      if mark.row == 0 then
        state.content_row_start = start_row + 1
        table.insert(state.marks.header, result)
      end
    end
  end
end

--- Creates an alias buffer.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil, header: { data: table }, suggestions: table}: Options for the buffer.
function M.aliases_buffer(filetype, callback, opts)
  local bufname = "kubectl_aliases"
  local buf = get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname, "prompt")
    vim.keymap.set("n", "q", function()
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.close()
    end, { buffer = buf, silent = true })
  end

  local win = layout.aliases_layout(buf, filetype, opts.title or "")

  vim.fn.prompt_setcallback(buf, function(input)
    callback(input)
    vim.cmd("stopinsert")
    api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.close()
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, filetype, "", bufname)
  layout.set_win_options(win)
  return buf
end

--- Creates a filter buffer.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil, header: { data: table }}: Options for the buffer.
function M.filter_buffer(filetype, callback, opts)
  local bufname = "kubectl_filter"
  local buf = get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname, "prompt")
    vim.keymap.set("n", "q", function()
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.close()
    end, { buffer = buf, silent = true })
  end

  local win = layout.filter_layout(buf, filetype, opts.title or "")

  vim.fn.prompt_setcallback(buf, function(input)
    input = vim.trim(input)
    callback(input)
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

  layout.set_buf_options(buf, filetype, "", bufname)
  layout.set_win_options(win)
  return buf
end

--- Creates a confirmation buffer.
--- @param prompt string: The prompt to display.
--- @param filetype string: The filetype of the buffer.
--- @param onConfirm function: The function to call on confirmation.
--- @param opts { syntax: string|nil, content: table|nil, marks: table|nil, width: number|nil }|nil: Options for the buffer.
--- @return integer, table: The buffer and window config.
function M.confirmation_buffer(prompt, filetype, onConfirm, opts)
  opts = opts or {}
  local bufname = "kubectl_confirmation"
  local buf = get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname)
  end
  local win = layout.float_dynamic_layout(buf, opts.syntax or filetype, prompt)

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

  layout.set_buf_options(buf, filetype, opts.syntax or filetype, bufname)
  layout.set_win_options(win)

  M.apply_marks(buf, opts.marks, nil)

  local win_config = layout.win_size_fit_content(buf, 2)

  local padding = string.rep(" ", win_config.width / 2)
  M.set_content(buf, { content = { padding .. "[y]es [n]o" } })

  return buf, win_config
end

--- Creates a namespace buffer.
--- @param filetype string: The filetype of the buffer.
--- @param title string|nil: The filetype of the buffer.
--- @param opts { header: { data: table }, prompt: boolean, syntax: string}|nil: Options for the buffer.
function M.floating_dynamic_buffer(filetype, title, callback, opts)
  opts = opts or {}
  local bufname = title or filetype
  local buf = get_buffer_by_name(bufname)

  if not buf then
    if opts.prompt then
      buf = create_buffer(bufname, "prompt")
    else
      buf = create_buffer(bufname)
    end
    vim.keymap.set("n", "q", function()
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.close()
    end, { buffer = buf, silent = true })
  end

  local win = layout.float_dynamic_layout(buf, opts.syntax or filetype, title or "")

  if opts.prompt then
    vim.fn.prompt_setcallback(buf, function(input)
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.close()
      vim.api.nvim_input("gr")

      callback(input)
    end)

    vim.cmd("startinsert")
  end

  layout.set_buf_options(buf, filetype, "", bufname)
  layout.set_win_options(win)
  layout.win_size_fit_content(buf, 2)
  return buf
end

--- @param buf number: Buffer number
--- @param opts { content: table, marks: table,  header: { data: table }}
function M.set_content(buf, opts)
  opts.header = opts.header or {}
  set_buffer_lines(buf, opts.header.data, opts.content)
  M.apply_marks(buf, opts.marks, opts.header)

  api.nvim_set_option_value("modified", false, { buf = buf })
end

--- Creates a floating buffer.
--- @param filetype string: The filetype of the buffer.
--- @param title string: The buffer title
--- @param syntax string?: The buffer title
--- @param win integer?: The buffer title
--- @return integer, integer: The buffer and win number.
function M.floating_buffer(filetype, title, syntax, win)
  local bufname = title or "kubectl_float"
  local buf = get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname)
  end

  local _, is_valid = pcall(vim.api.nvim_win_is_valid, win)
  if not win or not is_valid then
    win = layout.float_layout(buf, filetype, title or "")
    layout.set_win_options(win)
  end

  layout.set_buf_options(buf, filetype, syntax or filetype, bufname)

  vim.keymap.set("n", "q", function()
    vim.cmd.close()
  end, { buffer = buf, silent = true })

  M.set_content(buf, { content = { "Loading..." } })
  return buf, win
end

--- Creates or updates a buffer.
--- @param filetype string: The filetype of the buffer.
--- @param title string: The buffer title
function M.buffer(filetype, title)
  local bufname = title or "kubectl"
  local buf = get_buffer_by_name(bufname)
  local win = layout.main_layout()

  if not buf then
    buf = create_buffer(bufname)
    layout.set_buf_options(buf, filetype, filetype, bufname)
    layout.set_win_options(win)
  end

  api.nvim_set_current_buf(buf)

  return buf
end

--- Creates or updates a notification buffer.
--- @param opts { width: integer|nil, close: boolean|nil, append: boolean|nil }: Options for the buffer.
function M.notification_buffer(opts)
  opts.width = opts.width or 40
  local bufname = "notification"
  local marks = {}
  local buf = get_buffer_by_name(bufname)

  if opts.close then
    local _, _ = pcall(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
    return
  end

  if not buf then
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
