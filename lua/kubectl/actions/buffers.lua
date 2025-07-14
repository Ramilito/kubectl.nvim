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

--- Returns a list of window IDs that are currently showing a buffer
--- with the given name. If no such buffer exists, returns an empty table.
---@param bufname string
---@return number[] window_ids
function M.get_windows_by_name(bufname)
  -- Step 1: Find the buffer number for the given name (if it exists).
  local bufnr = vim.fn.bufnr(bufname, false)
  if bufnr == -1 then
    -- Buffer with that name does not exist, so no windows will have it.
    return {}
  end

  -- Step 2: Iterate over all windows, collecting those that have bufnr loaded.
  local matching_wins = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local win_bufnr = vim.api.nvim_win_get_buf(winid)
    if win_bufnr == bufnr then
      table.insert(matching_wins, winid)
    end
  end
  return matching_wins
end

--- Gets buffer number by name
--- @param bufname string: The name of the buffer
--- @return integer|nil: The buffer number
function M.get_buffer_by_name(bufname)
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
    pcall(vim.api.nvim_buf_set_lines, buf, 0, #header, false, header)
    pcall(vim.api.nvim_buf_set_lines, buf, #header, -1, false, content)
  else
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, content)
  end
end

--- Applies marks to a buffer.
--- @param bufnr integer: The buffer number.
--- @param marks table|nil: The marks to apply (optional).
--- @param header table|nil: The header data (optional).
function M.apply_marks(bufnr, marks, header)
  if not bufnr then
    return
  end
  local ns_id = api.nvim_create_namespace("__kubectl_views")
  pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
  local local_marks = marks
  local local_header = header
  state.marks.ns_id = ns_id

  local is_float = false
  -- TODO: Extract column header management
  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative ~= "" then
      is_float = true
    end
  end
  if not is_float then
    state.marks.header = {}
  end

  vim.schedule(function()
    if local_header and local_header.marks then
      for _, mark in ipairs(local_header.marks) do
        pcall(api.nvim_buf_set_extmark, bufnr, ns_id, mark.row, mark.start_col, {
          end_line = mark.row,
          end_col = mark.end_col,
          hl_group = mark.hl_group,
          hl_eol = mark.hl_eol or nil,
          virt_text = mark.virt_text or nil,
          virt_text_pos = mark.virt_text_pos or nil,
          virt_lines_above = mark.virt_lines_above or nil,
          virt_text_win_col = mark.virt_text_win_col or nil,
          ephemeral = mark.ephemeral,
        })
      end
    end
    if local_marks then
      for _, mark in ipairs(local_marks) do
        -- adjust for content not being at first row
        local start_row = mark.row
        if local_header and local_header.data then
          start_row = start_row + #local_header.data
        end
        local ok, result = pcall(api.nvim_buf_set_extmark, bufnr, ns_id, start_row, mark.start_col, {
          end_line = start_row,
          end_col = mark.end_col or nil,
          hl_eol = mark.hl_eol or nil,
          hl_group = mark.hl_group or nil,
          hl_mode = mark.hl_mode or nil,
          line_hl_group = mark.line_hl_group or nil,
          virt_text = mark.virt_text or nil,
          virt_text_pos = mark.virt_text_pos or nil,
          right_gravity = mark.right_gravity,
          sign_text = mark.sign_text or nil,
          sign_hl_group = mark.sign_hl_group or nil,
        })
				-- TODO: Extract column header management
        -- the first row is always column headers, we save that so other content can use it
        if not is_float and ok and mark.row == 0 then
          state.content_row_start = start_row + 1
          table.insert(state.marks.header, result)
        end
      end
    end
  end)
end

function M.fit_to_content(buf, win, offset)
  local win_config = layout.win_size_fit_content(buf, win, offset or 2)
  return win_config
end

--- Creates an alias buffer.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil }: Options for the buffer.
function M.aliases_buffer(filetype, callback, opts)
  local bufname = "kubectl_aliases"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname, "prompt")
  end

  local win = layout.float_dynamic_layout(buf, filetype, opts.title)

  vim.fn.prompt_setcallback(buf, function(input)
    callback(input)
    vim.cmd("stopinsert")
    api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.fclose()
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, filetype, "", bufname)
  layout.set_win_options(win)
  return buf, win
end

--- Creates a filter buffer.
--- @param filetype string: The filetype of the buffer.
--- @param callback function: The callback function.
--- @param opts { title: string|nil, header: { data: table }}: Options for the buffer.
function M.filter_buffer(filetype, callback, opts)
  local bufname = "kubectl_filter"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname, "prompt")
  end

  local win = layout.float_dynamic_layout(buf, filetype, opts.title or "")

  vim.fn.prompt_setcallback(buf, function(input)
    input = vim.trim(input)
    callback(input)
    if not input then
      state.setFilter("")
    else
      state.setFilter(input)
    end

    api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.fclose()
    vim.api.nvim_input("<Plug>(kubectl.refresh)")
  end)

  vim.cmd("startinsert")

  layout.set_buf_options(buf, filetype, "", bufname)
  layout.set_win_options(win)
  return buf, win
end

--- Creates a confirmation buffer.
--- @param prompt string: The prompt to display.
--- @param filetype string: The filetype of the buffer.
--- @param onConfirm function: The function to call on confirmation.
-- luacheck: no max line length
--- @param opts { syntax: string|nil, content: table|nil, marks: table|nil, width: number|nil }|nil: Options for the buffer.
--- @return integer, table, integer: The buffer and window config.
function M.confirmation_buffer(prompt, filetype, onConfirm, opts)
  opts = opts or {}
  local bufname = "kubectl_confirmation"
  local buf = M.get_buffer_by_name(bufname)

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

  layout.set_buf_options(buf, filetype, opts.syntax or filetype, bufname)
  layout.set_win_options(win)

  M.apply_marks(buf, opts.marks, nil)

  local win_config = M.fit_to_content(buf, win, 2)

  local padding = string.rep(" ", win_config.width / 2)
  M.set_content(buf, { content = { padding .. "[y]es [n]o" } })

  return buf, win_config, win
end

--- Creates a namespace buffer.
--- @param filetype string: The filetype of the buffer.
--- @param title string|nil: The filetype of the buffer.
--- @param callback function|nil: The callback function.
--- @param opts { header: { data: table }, prompt: boolean, syntax: string}|nil: Options for the buffer.
function M.floating_dynamic_buffer(filetype, title, callback, opts)
  opts = opts or {}
  local bufname = (filetype .. " | " .. title) or "kubectl_dynamic_float"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    if opts.prompt then
      buf = create_buffer(bufname, "prompt")
    else
      buf = create_buffer(bufname)
    end
  end

  local win = layout.float_dynamic_layout(buf, opts.syntax or filetype, title or "")

  if opts.prompt then
    vim.fn.prompt_setcallback(buf, function(input)
      api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd.fclose()
      vim.api.nvim_input("<Plug>(kubectl.refresh)")

      if callback ~= nil then
        callback(input)
      end
    end)

    vim.cmd("startinsert")
  end

  layout.set_buf_options(buf, filetype, "", bufname)
  layout.set_win_options(win)
  M.fit_to_content(buf, win, 2)

  state.set_buffer_state(buf, filetype, M.floating_dynamic_buffer, { filetype, title, callback, opts })
  return buf, win
end

--- Sets buffer content.
--- @param buf number: Buffer number
--- @param opts { content: table, marks: table,  header: { data: table }}
function M.set_content(buf, opts)
  opts.header = opts.header or {}
  set_buffer_lines(buf, opts.header.data, opts.content)
  M.apply_marks(buf, opts.marks, opts.header)

  pcall(api.nvim_set_option_value, "modified", false, { buf = buf })
end

--- Creates a floating buffer.
--- @param filetype string: The filetype of the buffer.
--- @param title string: The buffer title
--- @param syntax string?: The buffer title
--- @param win integer?: The buffer title
--- @return integer, integer: The buffer and win number.
function M.floating_buffer(filetype, title, syntax, win)
  local bufname = (filetype .. " | " .. title) or "kubectl_float"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    buf = create_buffer(bufname)
    M.set_content(buf, { content = { "Loading..." } })
  end

  local _, is_valid = pcall(vim.api.nvim_win_is_valid, win)
  if not win or not is_valid then
    win = layout.float_layout(buf, filetype, title or "")
    layout.set_win_options(win)
  end

  layout.set_buf_options(buf, filetype, syntax or filetype, bufname)

  state.set_buffer_state(buf, filetype, M.floating_buffer, { filetype, title, syntax, win })

  return buf, win
end

function M.header_buffer(win)
  local bufname = "kubectl_header"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, bufname)
    M.set_content(buf, { content = { "Loading..." } })
  end
  local width = 50
  local height = 10

  local total_lines = vim.o.lines
  local row = total_lines - height - 1
  if row < 0 then
    row = 0
  end

  local total_cols = vim.o.columns
  local col = math.floor((total_cols - width))
  if col < 0 then
    col = 0
  end

  local win_opts = {
    relative = "editor",
    anchor = "NW",
    width = col,
    height = height,
    row = row,
    col = total_cols,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  }

  local _, is_valid = pcall(vim.api.nvim_win_is_valid, win)
  if not win or not is_valid then
    win = vim.api.nvim_open_win(buf, false, win_opts)
  end

  vim.api.nvim_set_option_value("winblend", 20, { win = win })
  vim.api.nvim_set_option_value("wrap", true, { win = win })

  return buf, win
end

--- Creates or updates a buffer.
--- @param filetype string: The filetype of the buffer.
--- @param title string: The buffer title
function M.buffer(filetype, title)
  local bufname = title or "kubectl"
  local buf = M.get_buffer_by_name(bufname)
  local win = layout.main_layout()

  if not buf then
    buf = create_buffer(bufname)
    vim.schedule(function()
      layout.set_win_options(win)
      layout.set_buf_options(buf, filetype, filetype, bufname)
      vim.api.nvim_set_option_value("statusline", " ", { win = win })
    end)
  end

  api.nvim_set_current_buf(buf)
  state.set_session(bufname)

  return buf, win
end

return M
