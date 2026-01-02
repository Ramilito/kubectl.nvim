--- Native Neovim drift view - no ratatui, pure Lua rendering.
--- Compares local manifests against deployed cluster state.

local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")

local M = {}

M.definition = {
  resource = "drift",
  ft = "k8s_drift_native",
  title = "Drift",
  hints = {
    { key = "<Plug>(kubectl.drift_path)", desc = "path" },
    { key = "<Plug>(kubectl.drift_filter)", desc = "filter" },
    { key = "<Plug>(kubectl.drift_refresh)", desc = "refresh" },
    { key = "<Plug>(kubectl.drift_switch_pane)", desc = "switch pane" },
    { key = "<Plug>(kubectl.drift_close)", desc = "quit" },
  },
  panes = {
    { title = "Resources", width = 0.35 },
    { title = "Diff Preview", width = 0.65 },
  },
}

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace("kubectl_drift")

-- Icons
local ICON_CHANGED = "~"
local ICON_UNCHANGED = "✓"
local ICON_ERROR = "✗"

---@class DriftState
---@field path string Current path
---@field entries table[] Flattened resource entries
---@field counts table Status counts {changed, unchanged, errors}
---@field hide_unchanged boolean Filter flag
---@field builder table The resource builder
---@field list_buf number Resource list buffer
---@field list_win number Resource list window
---@field diff_buf number Diff preview buffer
---@field diff_win number Diff preview window

---@type DriftState|nil
local state = nil

--- Get drift results from Rust.
---@param path string
---@param hide_unchanged boolean
---@return table {entries, counts, build_error}
local function get_drift_results(path, hide_unchanged)
  if path == "" then
    return { entries = {}, counts = { changed = 0, unchanged = 0, errors = 0 } }
  end

  local client = require("kubectl.client")
  local ok, result = pcall(client.get_drift, path, hide_unchanged)
  if not ok then
    vim.notify("get_drift failed: " .. tostring(result), vim.log.levels.ERROR)
    return { entries = {}, counts = { changed = 0, unchanged = 0, errors = 0 } }
  end

  if result.build_error then
    vim.notify("Build error: " .. result.build_error, vim.log.levels.WARN)
  end

  return result
end

--- Render the resource list buffer.
---@param buf number
---@param entries table[]
---@param path string
---@param hide_unchanged boolean
---@param counts table
local function render_list(buf, entries, path, hide_unchanged, counts)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local lines = {}
  local marks = {}

  -- Summary line
  local summary = string.format(
    " %s │ %d changed │ %d unchanged │ %d errors%s",
    path ~= "" and path or "(no path)",
    counts.changed,
    counts.unchanged,
    counts.errors,
    hide_unchanged and " │ [filtered]" or ""
  )
  table.insert(lines, summary)
  table.insert(marks, { row = #lines - 1, start_col = 0, end_col = #path + 2, hl_group = hl.symbols.header })

  -- Empty line
  table.insert(lines, "")

  -- Resource entries
  for _, entry in ipairs(entries) do
    local icon, entry_hl
    if entry.status == "changed" then
      icon, entry_hl = ICON_CHANGED, hl.symbols.debug
    elseif entry.status == "error" then
      icon, entry_hl = ICON_ERROR, hl.symbols.error
    else
      icon, entry_hl = ICON_UNCHANGED, hl.symbols.info
    end

    local diff_info = entry.diff_lines > 0 and string.format(" (%d)", entry.diff_lines) or ""
    local line = string.format("%s %s/%s%s", icon, entry.kind, entry.name, diff_info)
    table.insert(lines, line)

    local row = #lines - 1
    table.insert(marks, { row = row, start_col = 0, end_col = #line - #diff_info, hl_group = entry_hl })
    if diff_info ~= "" then
      table.insert(marks, { row = row, start_col = #line - #diff_info, end_col = #line, hl_group = hl.symbols.gray })
    end
  end

  -- Show prompt if no path
  if path == "" then
    table.insert(lines, "")
    table.insert(lines, "        Press 'p' to select a path")
    table.insert(marks, { row = #lines - 1, start_col = 14, end_col = 17, hl_group = hl.symbols.pending })
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply highlights using buffers module for consistent handling
  buffers.apply_marks(buf, marks, {})

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

--- Render the diff preview buffer.
---@param buf number
---@param entry table|nil
local function render_diff(buf, entry)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local lines = {}
  local marks = {}

  if not entry then
    table.insert(lines, "Select a resource to view diff")
    table.insert(marks, { row = 0, col = 0, end_col = #lines[1], hl = "KubectlGray" })
  elseif entry.error then
    table.insert(lines, "Error:")
    table.insert(lines, entry.error)
    table.insert(marks, { row = 0, col = 0, end_col = 6, hl = "KubectlError" })
    table.insert(marks, { row = 1, col = 0, end_col = #entry.error, hl = "KubectlError" })
  elseif entry.diff then
    for i, line in ipairs(vim.split(entry.diff, "\n")) do
      table.insert(lines, line)
      local row = i - 1
      local hl_group
      if line:match("^%+") and not line:match("^%+%+%+") then
        hl_group = "DiffAdd"
      elseif line:match("^%-") and not line:match("^%-%-%-") then
        hl_group = "DiffDelete"
      elseif line:match("^@@") then
        hl_group = "KubectlPending"
      else
        hl_group = "KubectlGray"
      end
      table.insert(marks, { row = row, col = 0, end_col = #line, hl = hl_group })
    end
  else
    table.insert(lines, ICON_UNCHANGED .. " No differences")
    table.insert(marks, { row = 0, col = 0, end_col = #lines[1], hl = "KubectlInfo" })
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for _, mark in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, mark.row, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

--- Update the diff preview based on cursor position.
local function update_diff_preview()
  if not state then
    return
  end

  -- Get cursor line (1-indexed), subtract summary + empty line (hints are in separate window)
  local cursor_line = vim.api.nvim_win_get_cursor(state.list_win)[1]
  local entry_idx = cursor_line - 2 -- summary line + empty line

  local entry = state.entries[entry_idx]
  render_diff(state.diff_buf, entry)
end

--- Refresh the view with current path.
local function refresh()
  if not state then
    return
  end

  local result = get_drift_results(state.path, state.hide_unchanged)
  state.entries = result.entries
  state.counts = result.counts

  state.builder.renderHints()
  render_list(state.list_buf, state.entries, state.path, state.hide_unchanged, state.counts)
  update_diff_preview()
end

--- Toggle the unchanged filter.
local function toggle_filter()
  if not state then
    return
  end

  state.hide_unchanged = not state.hide_unchanged

  local result = get_drift_results(state.path, state.hide_unchanged)
  state.entries = result.entries
  state.counts = result.counts

  render_list(state.list_buf, state.entries, state.path, state.hide_unchanged, state.counts)
  update_diff_preview()
end

--- Simple directory picker using existing helpers.
---@param cwd string
---@param on_select fun(path: string|nil)
local function open_dir_picker(cwd, on_select)
  local current_dir = cwd
  local entries = {}
  local picker_buf, picker_win

  local function render()
    entries = {}
    local lines = {}
    local marks = {}

    -- Header with current path and help
    table.insert(lines, " " .. current_dir)
    table.insert(marks, { row = 0, start_col = 0, end_col = #lines[1], hl_group = hl.symbols.header })

    table.insert(lines, " <CR>:open dir/select file  <C-y>:select dir  <BS>:up  q:cancel")
    table.insert(marks, { row = 1, start_col = 0, end_col = #lines[2], hl_group = hl.symbols.gray })

    -- Parent directory
    table.insert(entries, { name = "..", path = vim.fn.fnamemodify(current_dir, ":h"), is_dir = true })
    table.insert(lines, "  ../")
    table.insert(marks, { row = 2, start_col = 0, end_col = #lines[3], hl_group = hl.symbols.pending })

    -- List directory contents (directories first, then files)
    local items = vim.fn.readdir(current_dir)
    table.sort(items, function(a, b)
      local a_is_dir = vim.fn.isdirectory(current_dir .. "/" .. a) == 1
      local b_is_dir = vim.fn.isdirectory(current_dir .. "/" .. b) == 1
      if a_is_dir ~= b_is_dir then
        return a_is_dir
      end
      return a < b
    end)

    for _, name in ipairs(items) do
      if name:sub(1, 1) ~= "." then
        local full_path = current_dir .. "/" .. name
        local is_dir = vim.fn.isdirectory(full_path) == 1
        table.insert(entries, { name = name, path = full_path, is_dir = is_dir })
        local display = is_dir and ("  " .. name .. "/") or ("  " .. name)
        table.insert(lines, display)
        table.insert(marks, {
          row = #lines - 1,
          start_col = 0,
          end_col = #display,
          hl_group = is_dir and hl.symbols.info or hl.symbols.gray,
        })
      end
    end

    buffers.set_content(picker_buf, { content = lines, marks = marks })
    buffers.fit_to_content(picker_buf, picker_win, 2)

    -- Position cursor on first entry (after header)
    pcall(vim.api.nvim_win_set_cursor, picker_win, { 3, 0 })
  end

  local function get_selected_entry()
    local cursor_line = vim.api.nvim_win_get_cursor(picker_win)[1]
    local entry_idx = cursor_line - 2 -- Subtract header lines
    return entries[entry_idx]
  end

  local function close_picker()
    if vim.api.nvim_win_is_valid(picker_win) then
      vim.api.nvim_win_close(picker_win, true)
    end
  end

  -- Create buffer and window
  picker_buf, picker_win = buffers.floating_dynamic_buffer("k8s_dir_picker", " Select Directory ", nil, {})

  -- Define Plug mappings
  vim.keymap.set("n", "<Plug>(kubectl.dir_open)", function()
    local entry = get_selected_entry()
    if not entry then
      return
    end
    if entry.is_dir then
      current_dir = entry.path
      render()
    else
      close_picker()
      on_select(entry.path)
    end
  end, { buffer = picker_buf, noremap = true, silent = true, desc = "Open directory or select file" })

  vim.keymap.set("n", "<Plug>(kubectl.dir_select)", function()
    close_picker()
    on_select(current_dir)
  end, { buffer = picker_buf, noremap = true, silent = true, desc = "Select current directory" })

  vim.keymap.set("n", "<Plug>(kubectl.dir_up)", function()
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
    render()
  end, { buffer = picker_buf, noremap = true, silent = true, desc = "Go to parent directory" })

  vim.keymap.set("n", "<Plug>(kubectl.dir_cancel)", function()
    close_picker()
    on_select(nil)
  end, { buffer = picker_buf, noremap = true, silent = true, desc = "Cancel" })

  -- Map keys to Plug targets
  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(picker_buf, "n", "<CR>", "<Plug>(kubectl.dir_open)", map_opts)
  vim.api.nvim_buf_set_keymap(picker_buf, "n", "<C-y>", "<Plug>(kubectl.dir_select)", map_opts)
  vim.api.nvim_buf_set_keymap(picker_buf, "n", "<BS>", "<Plug>(kubectl.dir_up)", map_opts)
  vim.api.nvim_buf_set_keymap(picker_buf, "n", "q", "<Plug>(kubectl.dir_cancel)", map_opts)
  vim.api.nvim_buf_set_keymap(picker_buf, "n", "<Esc>", "<Plug>(kubectl.dir_cancel)", map_opts)

  render()
end

--- Prompt for a directory path.
local function pick_path()
  if not state then
    return
  end

  local start_dir = state.path ~= "" and state.path or vim.fn.getcwd()
  local original_win = state.list_win

  open_dir_picker(start_dir, function(selected)
    if vim.api.nvim_win_is_valid(original_win) then
      vim.api.nvim_set_current_win(original_win)
    end
    if selected then
      state.path = selected
      refresh()
    end
  end)
end

--- Close the drift view.
local function close()
  if not state then
    return
  end

  local builder = state.builder
  state = nil
  if builder.frame then
    builder.frame.close()
  end
end

--- Switch focus to the other pane.
local function switch_pane()
  if not state then
    return
  end
  local current_win = vim.api.nvim_get_current_win()
  if current_win == state.list_win and vim.api.nvim_win_is_valid(state.diff_win) then
    vim.api.nvim_set_current_win(state.diff_win)
  elseif current_win == state.diff_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_set_current_win(state.list_win)
  end
end

-- Export functions for mappings.lua
M.pick_path = pick_path
M.toggle_filter = toggle_filter
M.refresh = refresh
M.close = close
M.switch_pane = switch_pane

--- Setup keymaps for the list buffer.
---@param buf number
local function setup_list_keymaps(buf)
  local opts = { noremap = true, silent = true }

  -- Define Plug mappings for this buffer
  vim.keymap.set("n", "<Plug>(kubectl.drift_path)", pick_path, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Plug>(kubectl.drift_filter)", toggle_filter, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Plug>(kubectl.drift_refresh)", refresh, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Plug>(kubectl.drift_switch_pane)", switch_pane, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Plug>(kubectl.drift_close)", close, { buffer = buf, noremap = true, silent = true })

  -- Map default keys to Plug targets on this specific buffer
  vim.api.nvim_buf_set_keymap(buf, "n", "p", "<Plug>(kubectl.drift_path)", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "f", "<Plug>(kubectl.drift_filter)", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "r", "<Plug>(kubectl.drift_refresh)", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "<Plug>(kubectl.drift_switch_pane)", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Plug>(kubectl.drift_close)", opts)
end

--- Setup keymaps for the diff buffer.
---@param buf number
local function setup_diff_keymaps(buf)
  local opts = { noremap = true, silent = true }

  -- Define Plug mappings for this buffer
  vim.keymap.set("n", "<Plug>(kubectl.drift_switch_pane)", switch_pane, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Plug>(kubectl.drift_close)", close, { buffer = buf, noremap = true, silent = true })

  -- Map default keys to Plug targets on this specific buffer
  vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "<Plug>(kubectl.drift_switch_pane)", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Plug>(kubectl.drift_close)", opts)
end

--- Open the native drift view.
---@param path string|nil
function M.open(path)
  -- Close existing view
  if state then
    close()
  end

  -- Create framed view using builder pattern
  local builder = manager.get_or_create(M.definition.resource)
  builder.view_framed(M.definition)

  local list_buf = builder.frame.panes[1].buf
  local list_win = builder.frame.panes[1].win
  local diff_buf = builder.frame.panes[2].buf
  local diff_win = builder.frame.panes[2].win

  -- Initialize state
  state = {
    path = path or "",
    entries = {},
    counts = { changed = 0, unchanged = 0, errors = 0 },
    hide_unchanged = false,
    builder = builder,
    list_buf = list_buf,
    list_win = list_win,
    diff_buf = diff_buf,
    diff_win = diff_win,
  }

  -- Setup keymaps
  setup_list_keymaps(list_buf)
  setup_diff_keymaps(diff_buf)

  -- Update diff on cursor move
  local augroup = vim.api.nvim_create_augroup("KubectlDriftNative", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = list_buf,
    callback = update_diff_preview,
  })

  -- Initial render
  refresh()

  return list_buf, list_win
end

return M
