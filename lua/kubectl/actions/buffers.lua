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
  vim.api.nvim_buf_set_name(buf, "kubectl://" .. bufname)
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
  local bufnr = vim.fn.bufnr("kubectl://" .. bufname, false)
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
  header = header or {}
  content = content or {}

  if #header == 0 and #content == 0 then
    return
  end

  local lines = vim.list_extend(vim.deepcopy(header), content)

  local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })

  if buftype == "prompt" then
    local prompt = vim.api.nvim_buf_line_count(buf) - 1
    vim.api.nvim_buf_set_lines(buf, 0, prompt, false, lines)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

--- Apply a single extmark to a buffer
---@param bufnr integer Buffer number
---@param ns_id integer Namespace ID
---@param mark table Mark definition
---@param row_offset number Row offset to apply
---@return boolean ok Whether the mark was applied successfully
---@return integer|nil extmark_id The extmark ID if successful
local function apply_single_mark(bufnr, ns_id, mark, row_offset)
  local row = mark.row + row_offset
  return pcall(api.nvim_buf_set_extmark, bufnr, ns_id, row, mark.start_col, {
    end_line = row,
    end_col = mark.end_col,
    hl_group = mark.hl_group,
    hl_eol = mark.hl_eol,
    hl_mode = mark.hl_mode,
    line_hl_group = mark.line_hl_group,
    virt_text = mark.virt_text,
    virt_text_pos = mark.virt_text_pos,
    virt_lines_above = mark.virt_lines_above,
    virt_text_win_col = mark.virt_text_win_col,
    right_gravity = mark.right_gravity,
    sign_text = mark.sign_text,
    sign_hl_group = mark.sign_hl_group,
    ephemeral = mark.ephemeral,
    priority = mark.priority,
  })
end

--- Initialize buffer state for sorting support.
---@param bufnr integer Buffer number
---@param ns_id integer Namespace ID
---@param header_row_offset integer Number of header lines (content starts after this)
function M.setup_buffer_marks_state(bufnr, ns_id, header_row_offset)
  local buf_state = state.get_buffer_state(bufnr)
  buf_state.ns_id = ns_id
  buf_state.content_row_start = header_row_offset + 1
end

--- Applies extmarks to a buffer for syntax highlighting and virtual text.
---@param bufnr integer Buffer number
---@param marks table|nil Content marks to apply
---@param header table|nil Header with { data: string[], marks: table[] }
function M.apply_marks(bufnr, marks, header)
  if not bufnr then
    return
  end

  local ns_id = api.nvim_create_namespace("__kubectl_views")
  local header_data = header and header.data
  local header_row_offset = header_data and #header_data or 0

  pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)

  -- Apply header marks
  if header and header.marks then
    for _, mark in ipairs(header.marks) do
      apply_single_mark(bufnr, ns_id, mark, 0)
    end
  end

  -- Apply content marks
  if marks then
    for _, mark in ipairs(marks) do
      apply_single_mark(bufnr, ns_id, mark, header_row_offset)
    end
  end

  M.setup_buffer_marks_state(bufnr, ns_id, header_row_offset)
end

function M.fit_to_content(buf, win, offset)
  local win_config = layout.win_size_fit_content(buf, win, offset or 2)
  return win_config
end

--- Fit a framed layout (hints + content pane) to content size
---@param frame table Frame object from view_framed (with hints_win, panes)
---@param offset? number Height offset for content pane (default 0)
function M.fit_framed_to_content(frame, offset)
  layout.fit_framed_to_content(frame, offset)
end

--- Creates an alias buffer.
--- @param filetype string: The filetype of the buffer.
--- @param opts { title: string|nil }: Options for the buffer.
function M.aliases_buffer(filetype, callback, opts)
  local bufname = "aliases"
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
  local bufname = "filter"
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
  local bufname = "confirmation"
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
-- luacheck: no max line length
--- @param opts { header: { data: table }, prompt: boolean, syntax: string, enter: boolean, relative: string, skip_fit: boolean, width: integer?, height: integer? }|nil
function M.floating_dynamic_buffer(filetype, title, callback, opts)
  opts = opts or {}
  local bufname = filetype or "dynamic_float"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    if opts.prompt then
      buf = create_buffer(bufname, "prompt")
    else
      buf = create_buffer(bufname)
    end
  end

  local win = layout.float_dynamic_layout(buf, opts.syntax or filetype, title or "", {
    relative = opts.relative,
    enter = opts.enter,
    skip_fit = opts.skip_fit,
    width = opts.width,
    height = opts.height,
  })

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
  if not opts.skip_fit then
    M.fit_to_content(buf, win, 2)
  end

  if title then
    state.picker_register(filetype, title, M.floating_dynamic_buffer, { filetype, title, callback, opts })
  end
  return buf, win
end

--- Sets buffer content.
---@param buf number Buffer number
---@param opts { content: table, marks: table, header: { data: table } }
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
  local bufname = (filetype .. " | " .. title) or "float"
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

  state.picker_register(filetype, bufname, M.floating_buffer, { filetype, title, syntax })

  return buf, win
end

function M.header_buffer(win)
  local bufname = "header"
  local buf = M.get_buffer_by_name(bufname)

  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "kubectl://" .. bufname)
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

  local config = require("kubectl.config")
  vim.api.nvim_set_option_value("winblend", config.options.headers.blend, { win = win })
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
    end)
  end

  -- Clear selections when opening/switching to a view buffer
  state.set_buffer_selections(buf, {})

  api.nvim_set_current_buf(buf)
  state.set_session(bufname)

  return buf, win
end

---@class FramedPaneOpts
---@field title string|nil Window title
---@field width number|nil Width ratio (0-1) for multi-pane layouts
---@field prompt boolean|nil Whether this pane uses prompt buffer type

---@class FramedBufferConfig
---@field title string|nil Main title for the frame
---@field filetype string|nil Filetype for the first pane buffer
---@field panes FramedPaneOpts[] Pane configurations
---@field width number|nil Overall width ratio (default 0.8)
---@field height number|nil Overall height ratio (default 0.8)
---@field recreate_func function|nil Function to recreate the view for picker restoration
---@field recreate_args table|nil Arguments to pass to recreate_func

---@class FramedBufferResult
---@field hints_buf number Hints buffer
---@field hints_win number Hints window
---@field panes { buf: number, win: number }[] Array of pane buffer/window pairs
---@field close fun() Close all windows

--- Creates a framed floating layout with hints bar at top and content panes below.
--- Buffer creation and options are handled here, window positioning by layout.lua
--- @param opts FramedBufferConfig
--- @return FramedBufferResult
function M.framed_buffer(opts)
  -- Build breadcrumb-style buffer name: kubectl://{filetype}/{resource}/{namespace}/{name}
  -- Title format is: "{resource} | {name} | {namespace}" or "{resource} | {name}"
  local buf_base = "kubectl://" .. (opts.filetype or "frame")
  if opts.title then
    local parts = vim.split(opts.title, "|")
    local resource = parts[1] and vim.trim(parts[1]) or nil
    local name = parts[2] and vim.trim(parts[2]) or nil
    local namespace = parts[3] and vim.trim(parts[3]) or nil
    -- Build path as: resource/namespace/name (namespace may be nil)
    local path_parts = vim.iter({ resource, namespace, name })
      :filter(function(v)
        return v and v ~= ""
      end)
      :map(function(v)
        return v:gsub("[/\\]", "_")
      end)
      :totable()
    if #path_parts > 0 then
      buf_base = buf_base .. "/" .. table.concat(path_parts, "/")
    end
  end

  local hints_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(hints_buf, buf_base .. "/hints")

  local pane_bufs = {}
  for i, pane_opts in ipairs(opts.panes) do
    if pane_opts.prompt then
      pane_bufs[i] = api.nvim_create_buf(false, true)
      api.nvim_set_option_value("buftype", "prompt", { buf = pane_bufs[i] })
    else
      pane_bufs[i] = api.nvim_create_buf(false, true)
    end
    -- First pane gets clean name, additional panes get numbered suffix
    local pane_name = i == 1 and buf_base or (buf_base .. "/pane_" .. i)
    api.nvim_buf_set_name(pane_bufs[i], pane_name)
  end

  -- Create windows via layout
  local win_result = layout.float_framed_windows(
    { hints_buf = hints_buf, pane_bufs = pane_bufs },
    { title = opts.title, panes = opts.panes, width = opts.width, height = opts.height }
  )

  -- Set buffer options for hints buffer
  api.nvim_set_option_value("buftype", "nofile", { buf = hints_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = hints_buf })
  api.nvim_set_option_value("swapfile", false, { buf = hints_buf })
  api.nvim_set_option_value("modifiable", false, { buf = hints_buf })

  -- Set buffer options for pane buffers
  for i, pane_buf in ipairs(pane_bufs) do
    local pane_opts = opts.panes[i]
    -- Don't override buftype for prompt buffers
    if not pane_opts.prompt then
      api.nvim_set_option_value("buftype", "nofile", { buf = pane_buf })
    end
    api.nvim_set_option_value("bufhidden", "wipe", { buf = pane_buf })
    api.nvim_set_option_value("swapfile", false, { buf = pane_buf })

    if i == 1 and opts.filetype then
      api.nvim_set_option_value("filetype", opts.filetype, { buf = pane_buf })
    end
  end

  -- Build panes result
  local panes = {}
  for i, pane_buf in ipairs(pane_bufs) do
    panes[i] = { buf = pane_buf, win = win_result.pane_wins[i] }
  end

  -- Close function
  local function close()
    if api.nvim_win_is_valid(win_result.hints_win) then
      api.nvim_win_close(win_result.hints_win, true)
    end
    for _, pane in ipairs(panes) do
      if api.nvim_win_is_valid(pane.win) then
        api.nvim_win_close(pane.win, true)
      end
    end
  end

  -- Setup cleanup autocmd on first pane close
  local augroup = api.nvim_create_augroup("KubectlFramedBuffer_" .. hints_buf, { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(panes[1].win),
    once = true,
    callback = function()
      close()
      pcall(api.nvim_del_augroup_by_id, augroup)
    end,
  })

  -- Register for picker
  if opts.filetype and opts.title and opts.recreate_func then
    state.picker_register(opts.filetype, opts.title, opts.recreate_func, opts.recreate_args or {})
  end

  return {
    hints_buf = hints_buf,
    hints_win = win_result.hints_win,
    panes = panes,
    close = close,
  }
end

return M
