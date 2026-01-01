--- Native Neovim drift view - no ratatui, pure Lua rendering.
--- Compares local manifests against deployed cluster state.

local M = {}

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace("kubectl_drift")

-- Icons
local ICON_CHANGED = "~"
local ICON_UNCHANGED = "✓"
local ICON_ERROR = "✗"

---@class DriftState
---@field path string Current path
---@field results table[] Diff results from kubediff
---@field entries table[] Flattened resource entries
---@field hide_unchanged boolean Filter flag
---@field list_buf number Resource list buffer
---@field list_win number Resource list window
---@field diff_buf number Diff preview buffer
---@field diff_win number Diff preview window

---@type DriftState|nil
local state = nil

--- Get diff results from Rust/kubediff.
---@param path string
---@return table[]
local function get_diff_results(path)
  if path == "" then
    return {}
  end

  local client = require("kubectl.client")
  -- Call kubediff via Rust and get results as Lua table
  local ok, results = pcall(client.kubediff, path)
  if not ok then
    vim.notify("kubediff failed: " .. tostring(results), vim.log.levels.ERROR)
    return {}
  end
  return results or {}
end

--- Build flattened entry list from results.
---@param results table[]
---@param hide_unchanged boolean
---@return table[]
local function build_entries(results, hide_unchanged)
  local entries = {}

  for _, target in ipairs(results) do
    for _, result in ipairs(target.results or {}) do
      local status
      if result.error then
        status = "error"
      elseif result.diff then
        status = "changed"
      else
        status = "unchanged"
      end

      if not (hide_unchanged and status == "unchanged") then
        table.insert(entries, {
          kind = result.kind or "Unknown",
          name = result.resource_name or "unknown",
          status = status,
          diff = result.diff,
          error = result.error,
          diff_lines = result.diff and #vim.split(result.diff, "\n") or 0,
        })
      end
    end
  end

  return entries
end

--- Count resources by status.
---@param results table[]
---@return table
local function count_statuses(results)
  local counts = { changed = 0, unchanged = 0, errors = 0 }

  for _, target in ipairs(results) do
    for _, result in ipairs(target.results or {}) do
      if result.error then
        counts.errors = counts.errors + 1
      elseif result.diff then
        counts.changed = counts.changed + 1
      else
        counts.unchanged = counts.unchanged + 1
      end
    end
  end

  return counts
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

  -- Help bar
  local help = "p:path │ f:filter │ r:refresh │ q:quit"
  table.insert(lines, help)
  table.insert(marks, { row = 0, col = 0, end_col = #help, hl = "KubectlGray" })

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
  table.insert(marks, { row = 1, col = 0, end_col = #path + 2, hl = "KubectlHeader" })

  -- Empty line
  table.insert(lines, "")

  -- Resource entries
  for _, entry in ipairs(entries) do
    local icon, hl_group
    if entry.status == "changed" then
      icon, hl_group = ICON_CHANGED, "KubectlDebug"
    elseif entry.status == "error" then
      icon, hl_group = ICON_ERROR, "KubectlError"
    else
      icon, hl_group = ICON_UNCHANGED, "KubectlInfo"
    end

    local diff_info = entry.diff_lines > 0 and string.format(" (%d)", entry.diff_lines) or ""
    local line = string.format("%s %s/%s%s", icon, entry.kind, entry.name, diff_info)
    table.insert(lines, line)

    local row = #lines - 1
    table.insert(marks, { row = row, col = 0, end_col = #line - #diff_info, hl = hl_group })
    if diff_info ~= "" then
      table.insert(marks, { row = row, col = #line - #diff_info, end_col = #line, hl = "KubectlGray" })
    end
  end

  -- Show prompt if no path
  if path == "" then
    table.insert(lines, "")
    table.insert(lines, "        Press 'p' to select a path")
    table.insert(marks, { row = #lines - 1, col = 14, end_col = 17, hl = "KubectlPending" })
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply highlights
  for _, mark in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, mark.row, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end

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

  -- Get cursor line (0-indexed, subtract header lines)
  local cursor_line = vim.api.nvim_win_get_cursor(state.list_win)[1]
  local entry_idx = cursor_line - 3 -- Help + summary + empty line

  local entry = state.entries[entry_idx]
  render_diff(state.diff_buf, entry)
end

--- Refresh the view with current path.
local function refresh()
  if not state then
    return
  end

  state.results = get_diff_results(state.path)
  state.entries = build_entries(state.results, state.hide_unchanged)

  local counts = count_statuses(state.results)
  render_list(state.list_buf, state.entries, state.path, state.hide_unchanged, counts)
  update_diff_preview()
end

--- Toggle the unchanged filter.
local function toggle_filter()
  if not state then
    return
  end

  state.hide_unchanged = not state.hide_unchanged
  state.entries = build_entries(state.results, state.hide_unchanged)

  local counts = count_statuses(state.results)
  render_list(state.list_buf, state.entries, state.path, state.hide_unchanged, counts)
  update_diff_preview()
end

--- Prompt for a new path.
local function pick_path()
  if not state then
    return
  end

  vim.ui.input({
    prompt = "Drift path: ",
    default = state.path,
    completion = "file",
  }, function(new_path)
    if new_path and new_path ~= "" then
      state.path = vim.fn.expand(new_path)
      refresh()
    end
  end)
end

--- Close the drift view.
local function close()
  if not state then
    return
  end

  local list_win = state.list_win
  local diff_win = state.diff_win
  state = nil

  if vim.api.nvim_win_is_valid(list_win) then
    vim.api.nvim_win_close(list_win, true)
  end
  if vim.api.nvim_win_is_valid(diff_win) then
    vim.api.nvim_win_close(diff_win, true)
  end
end

--- Setup keymaps for the drift view.
---@param buf number
local function setup_keymaps(buf)
  local opts = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set("n", "p", pick_path, opts)
  vim.keymap.set("n", "f", toggle_filter, opts)
  vim.keymap.set("n", "r", refresh, opts)
  vim.keymap.set("n", "q", close, opts)
end

--- Open the native drift view.
---@param path string|nil
function M.open(path)
  -- Close existing view
  if state then
    close()
  end

  -- Create floating window for split layout
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create list buffer and window (left pane, 35%)
  local list_buf = vim.api.nvim_create_buf(false, true)
  local list_width = math.floor(width * 0.35)
  local list_win = vim.api.nvim_open_win(list_buf, true, {
    relative = "editor",
    width = list_width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " Resources ",
    title_pos = "center",
  })

  -- Create diff buffer and window (right pane, 65%)
  local diff_buf = vim.api.nvim_create_buf(false, true)
  local diff_width = width - list_width - 1
  local diff_win = vim.api.nvim_open_win(diff_buf, false, {
    relative = "editor",
    width = diff_width,
    height = height,
    col = col + list_width + 1,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " Diff Preview ",
    title_pos = "center",
  })

  -- Set buffer options
  for _, buf in ipairs({ list_buf, diff_buf }) do
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  end

  vim.api.nvim_set_option_value("filetype", "k8s_drift_native", { buf = list_buf })
  vim.api.nvim_set_option_value("cursorline", true, { win = list_win })

  -- Initialize state
  state = {
    path = path or "",
    results = {},
    entries = {},
    hide_unchanged = false,
    list_buf = list_buf,
    list_win = list_win,
    diff_buf = diff_buf,
    diff_win = diff_win,
  }

  -- Setup keymaps
  setup_keymaps(list_buf)

  -- Update diff on cursor move
  local augroup = vim.api.nvim_create_augroup("KubectlDriftNative", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = list_buf,
    callback = update_diff_preview,
  })

  -- Cleanup on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(list_win),
    once = true,
    callback = function()
      close()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })

  -- Initial render
  refresh()

  return list_buf, list_win
end

return M
