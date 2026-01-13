local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local time = require("kubectl.utils.time")
local M = {}

--- Headers that cannot be hidden (always visible)
M.required_headers = { NAME = true, NAMESPACE = true }

--- Calculate column widths for table data
---@param rows table[]
---@param columns string[]
---@return table
local function calculate_column_widths(rows, columns)
  local widths = {}
  for _, row in ipairs(rows) do
    for _, column in pairs(columns) do
      if type(row[column]) == "table" then
        widths[column] = math.max(widths[column] or 0, #tostring(row[column].value))
      else
        widths[column] = math.max(widths[column] or 0, #tostring(row[column]))
      end
    end
  end

  return widths
end

--- Calculate and distribute extra padding
---@param widths  table     -- current column‑widths  (keyed by lower‑case header)
---@param headers string[]  -- column headers, in display order
---@param win     number?   -- window handle; defaults to current
local function calculate_extra_padding(widths, headers, win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  ---------------------------------------------------------------------------
  -- 1.  Minimum width for every column (text + “ | ” separator, etc.)
  ---------------------------------------------------------------------------
  local win_width = vim.api.nvim_win_get_width(win)
  local textoff = vim.fn.getwininfo(win)[1].textoff
  local text_width = win_width - textoff

  local separator_width = 3 -- space reserved for sort icon / “ | ”
  local total_width = 0

  for i, header in ipairs(headers) do
    local key = header:lower()
    local value_width = widths[key] or 0
    local col_width = math.max(#header, value_width) + separator_width

    if i == #headers then -- no trailing separator after the last col
      col_width = col_width - separator_width + 1
    end

    widths[key] = col_width
    total_width = total_width + col_width
  end

  ---------------------------------------------------------------------------
  -- 2.  Share the remaining room **across every column** (left‑aligned)
  ---------------------------------------------------------------------------
  local total_padding = text_width - total_width - 2
  if total_padding <= 0 then
    return
  end

  local ncols = #headers
  local base_padding = math.floor(total_padding / ncols)
  local remainder = total_padding % ncols

  for i, header in ipairs(headers) do
    local key = header:lower()
    local extra = (i <= remainder) and 1 or 0
    widths[key] = widths[key] + base_padding + extra
  end
end

--- Gets both global and buffer-local plug keymaps
--- @param headers table[] The header table
function M.get_plug_mappings(headers)
  local keymaps_table = {}
  local header_lookup = {}

  if not headers then
    return keymaps_table
  end

  local keymaps = vim.fn.maplist()

  for _, header in ipairs(headers) do
    header_lookup[header.key] =
      { desc = header.desc, long_desc = header.long_desc, sort_order = header.sort_order, global = header.global }
  end

  -- Iterate over keymaps and check if they match any header key
  for _, keymap in ipairs(keymaps) do
    local header = header_lookup[keymap.rhs]
    if header then
      table.insert(keymaps_table, {
        key = keymap.lhs,
        desc = header.desc,
        long_desc = header.long_desc,
        sort_order = header.sort_order,
        global = header.global,
      })
    end
  end

  -- Sort by key (change to desc if needed)
  table.sort(keymaps_table, function(a, b)
    if a.sort_order and not b.sort_order then
      return false
    elseif not a.sort_order and b.sort_order then
      return true
    else
      return a.key > b.key
    end
  end)
  return keymaps_table
end

--- Add a mark to the extmarks table
---@param extmarks table[]
---@param row number
---@param start_col number
---@param end_col number
---@param hl_group string
function M.add_mark(extmarks, row, start_col, end_col, hl_group)
  table.insert(extmarks, { row = row, start_col = start_col, end_col = end_col, hl_group = hl_group })
end

---@param headers table[]
---@param hints table[]
---@param marks table[]
local function addHeaderRow(headers, hints, marks)
  local DIVIDER = " | "
  local PREFIX = "Hints: "

  local function appendMapToLine(line, map, hintIndex)
    if #line > #PREFIX then
      local dividerStart = #line
      line = line .. DIVIDER
      M.add_mark(marks, hintIndex, dividerStart, #line, hl.symbols.success)
    end

    local lineStart = #line
    line = line .. map.key .. " " .. map.desc
    M.add_mark(marks, hintIndex, lineStart, lineStart + #map.key, hl.symbols.pending)

    return line
  end

  local localHintLine = PREFIX
  local globalHintLine = (" "):rep(#PREFIX)

  M.add_mark(marks, #hints, 0, #PREFIX, hl.symbols.success)
  local keymaps = M.get_plug_mappings(headers)
  local hasGlobal = false
  for _, map in ipairs(keymaps) do
    if map.global then
      hasGlobal = true
      globalHintLine = appendMapToLine(globalHintLine, map, #hints + 1)
    else
      localHintLine = appendMapToLine(localHintLine, map, #hints)
    end
  end

  table.insert(hints, localHintLine .. "\n")
  if hasGlobal then
    table.insert(hints, globalHintLine .. "\n")
  end
end

--- Adds the heartbeat element
---@param hints table The keymap hints
---@param marks table The extmarks
local function addHeartbeat(hints, marks)
  local padding = "   "
  if state.livez.ok then
    table.insert(marks, {
      row = #hints - 1,
      start_col = -1,
      virt_text = { { "Heartbeat: ", hl.symbols.note }, { "ok", hl.symbols.success }, { padding } },
      virt_text_pos = "right_align",
    })
  elseif state.livez.ok == nil then
    table.insert(marks, {
      row = #hints - 1,
      start_col = -1,
      virt_text = { { "Heartbeat: ", hl.symbols.note }, { "pending", hl.symbols.warning }, { padding } },
      virt_text_pos = "right_align",
    })
  else
    local current_time = os.time()
    local since = time.diff_str(current_time, state.livez.time_of_ok)
    table.insert(marks, {
      row = #hints - 1,
      start_col = -1,
      virt_text = {
        { "Heartbeat: ", hl.symbols.note },
        { "failed ", hl.symbols.error },
        { "(" .. since .. ")", hl.symbols.error },
        { padding },
      },
      virt_text_pos = "right_align",
    })
  end
end

--- Add context rows to the hints and marks tables
---@param context table
---@return table[]
local function addContextRows(context)
  local items = {}
  if not context.contexts then
    return items
  end
  local current_context = context.contexts[1]
  if current_context then
    table.insert(items, { label = "Context:", value = current_context.name, symbol = hl.symbols.pending })
    table.insert(items, { label = "User:", value = current_context.context.user })
  end

  -- Prepare the namespace and cluster information
  local namespace = state.getNamespace()
  table.insert(items, { label = "Namespace:", value = namespace, symbol = hl.symbols.pending })

  if context.clusters then
    table.insert(items, { label = "Cluster:", value = context.clusters[1].name })
  end

  return items
end

local function addVersionsRows(versions)
  local client_major = tonumber(versions.client.major)
  local client_minor = tonumber(versions.client.minor)
  local server_major = tonumber(versions.server.major)
  local server_minor = tonumber(versions.server.minor)
  local client_ver = client_major .. "." .. client_minor
  local server_ver = server_major .. "." .. server_minor
  local items = {}

  table.insert(items, { label = "Client:", value = client_ver })
  table.insert(items, { label = "Server:", value = server_ver })

  if client_ver == "0.0" then
    return items
  end

  -- https://kubernetes.io/releases/version-skew-policy/#kubectl
  if client_major ~= server_major then
    items[1].symbol = hl.symbols.error
  else
    local minor_diff = client_minor - server_minor
    if minor_diff > 1 or minor_diff < -1 then
      items[1].symbol = hl.symbols.error
    elseif minor_diff == 1 or minor_diff == -1 then
      items[1].symbol = hl.symbols.warning
    else -- minor_diff == 0
      items[1].symbol = hl.symbols.success
    end
  end
  return items
end

--- Add divider row
---@param hints table The keymap hints
---@param marks table The extmarks
function M.generateDividerRow(hints, marks)
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local text_width = win_width - vim.fn.getwininfo(win)[1].textoff
  local half_width = math.floor(text_width / 2)
  local padding = string.rep("-", half_width)
  local row = padding .. padding
  table.insert(marks, {
    row = #hints,
    start_col = 0,
    end_col = #padding + #padding,
    virt_text = {
      { padding, hl.symbols.success },
      { padding, hl.symbols.success },
    },
    virt_text_pos = "overlay",
  })
  table.insert(hints, row)
end

---@param divider { resource: string, count: string, filter: string }|nil
---@return string The formatted divider row
function M.generateDividerWinbar(divider, win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return ""
  end
  local text_width = vim.api.nvim_win_get_width(win)

  if not divider then
    return ("%#KubectlSuccess#%s%%*"):format(string.rep("-", text_width))
  end

  local resource = divider.resource or ""
  local count = divider.count or ""
  local filter = divider.filter or ""
  local bufnr = vim.api.nvim_win_get_buf(win)
  local selected_count = vim.tbl_count(state.getSelections(bufnr))

  if selected_count > 0 then
    count = ("%d/%s"):format(selected_count, count)
  end

  local center_text = table.concat({
    "%#KubectlHeader#",
    " ",
    resource,
    "(",
    "%#KubectlPending#",
    state.ns,
    "%#KubectlHeader#",
    ")",
    "[",
    "%#KubectlWhite#",
    count,
    "%#KubectlHeader#",
    "] ",
    filter ~= "" and ("</%#KubectlPending#" .. filter .. "%#KubectlHeader#> ") or "",
    "%*",
  })

  local center_len = #resource + #count + 5
  if filter ~= "" then
    center_len = center_len + #filter + 4
  end

  local total_pad = text_width - center_len
  local left_len = math.floor(total_pad / 2)
  local right_len = math.floor(total_pad - left_len)

  local left_pad = string.rep("-", left_len)
  local right_pad = string.rep("-", right_len)

  return table.concat({
    "%#KubectlSuccess#",
    left_pad,
    "%*",
    center_text,
    "%#KubectlSuccess#",
    right_pad,
    "%*",
  })
end

--- Generate header hints and marks
---@param headers table
---@param include_defaults boolean
---@param include_context boolean
---@return table, table
function M.generateHeader(headers, include_defaults, include_context)
  local hints = {}
  local marks = {}

  if not config.options.headers.enabled then
    return hints, marks
  end

  if include_defaults then
    local defaults = {
      { key = "<Plug>(kubectl.refresh)", desc = "reload", global = true },
      { key = "<Plug>(kubectl.alias_view)", desc = "aliases", global = true },
      { key = "<Plug>(kubectl.filter_view)", desc = "filter", global = true },
      { key = "<Plug>(kubectl.namespace_view)", desc = "namespace", global = true },
      { key = "<Plug>(kubectl.toggle_diagnostics)", desc = "diagnostics", global = true },
      { key = "<Plug>(kubectl.toggle_columns)", desc = "columns", global = true },
      { key = "<Plug>(kubectl.help)", desc = "help", global = true, sort_order = 100 },
      { key = "<Plug>(kubectl.toggle_headers)", desc = "toggle", global = true, sort_order = 200 },
    }
    for _, default in ipairs(defaults) do
      table.insert(headers, default)
    end
  end

  -- Add hints rows
  if config.options.headers.hints then
    addHeaderRow(headers, hints, marks)
  end

  local items = {}

  -- Add context rows
  if include_context and config.options.headers.context then
    if config.options.headers.hints then
      table.insert(hints, "\n")
    end
    local context = state.getContext()
    if context then
      vim.list_extend(items, addContextRows(context))
    end
  end

  -- Add versions
  if include_context and config.options.headers.skew.enabled then
    vim.list_extend(items, addVersionsRows(state.getVersions()))
  end

  local columns = { "label", "value" }
  local left_columns = {}

  -- Increase the third parameter to increase columns
  for i = 1, #items, 2 do
    table.insert(left_columns, items[i])
  end
  local column_widths = calculate_column_widths(left_columns, columns)

  local function format_item(item)
    local label = item.label .. string.rep(" ", column_widths["label"] - vim.fn.strdisplaywidth(item.label))
    local value = item.value .. string.rep(" ", column_widths["value"] - vim.fn.strdisplaywidth(item.value))
    return label, value
  end

  -- Increase the third parameter to increase columns
  for i = 1, #items, 2 do
    local left_label, left_value = format_item(items[i])
    local right_label, right_value = format_item(items[i + 1])

    local line = left_label .. " " .. left_value .. " │ " .. right_label .. " " .. right_value

    if items[i].symbol then
      M.add_mark(marks, #hints, #left_label, #left_label + #left_value + 1, items[i].symbol)
    end
    if i < #items - 2 then
      line = line .. "\n"
    end
    table.insert(hints, line)
  end

  -- Add heartbeat
  -- TODO: heartbeat should have it's own config option
  if include_context and config.options.headers.heartbeat then
    if #hints == 0 then
      hints = { "\n" }
    end
    addHeartbeat(hints, marks)
  end

  return vim.split(table.concat(hints, ""), "\n"), marks
end

--- Pretty print data in a table format
---@param data table[]
---@param headers string[]
---@param sort_by? table
---@param win? number
---@return table, table
function M.pretty_print(data, headers, sort_by, win)
  if headers == nil or data == nil then
    return {}, {}
  end
  local columns = {}
  for k, v in ipairs(headers) do
    columns[k] = v:lower()
  end
  local widths = calculate_column_widths(data, columns)

  -- adjust for headers being longer than max length content
  for key, value in pairs(widths) do
    widths[key] = math.max(#key, value)
  end

  calculate_extra_padding(widths, headers, win)
  local tbl = {}
  local extmarks = {}

  -- Create table header
  local header_line = {}
  if not sort_by or sort_by.current_word == "" then
    sort_by = { current_word = headers[1], order = "asc" }
  end

  local header_col_position = 0
  for i, header in ipairs(headers) do
    local column_width = widths[columns[i]] or 0
    local padding = string.rep(" ", column_width - #header)
    local value = header .. padding
    table.insert(header_line, value)

    local start_col = header_col_position
    local end_col = start_col + #header + 1

    if header == sort_by.current_word then
      table.insert(extmarks, {
        row = 0,
        start_col = end_col,
        virt_text = { { (sort_by.order == "asc" and "▲" or "▼"), hl.symbols.header } },
        virt_text_pos = "overlay",
      })
    end

    table.insert(extmarks, {
      row = 0,
      start_col = start_col,
      hl_mode = "combine",
      virt_text = { { header .. string.rep(" ", column_width), { hl.symbols.header } } },
      virt_text_pos = "overlay",
    })

    header_col_position = header_col_position + #value
  end
  table.insert(tbl, table.concat(header_line, ""))

  -- Get selections from per-buffer state
  local bufnr = win and vim.api.nvim_win_get_buf(win) or vim.api.nvim_get_current_buf()
  local selections = state.get_buffer_selections(bufnr)
  -- Create table rows
  for row_index, row in ipairs(data) do
    local is_selected = false
    if #selections > 0 then
      is_selected = M.is_selected(row, selections)
    end
    local row_line = {}
    local current_col_position = 0
    if is_selected then
      table.insert(extmarks, {
        row = row_index,
        start_col = 0,
        line_hl_group = hl.symbols.header,
      })
      table.insert(extmarks, {
        row = row_index,
        start_col = 0,
        sign_text = "»",
        sign_hl_group = "Note",
      })
    end

    for _, col in ipairs(columns) do
      local cell = row[col]
      local value, hl_group

      if type(cell) == "table" then
        value = tostring(cell.value)
        hl_group = cell.symbol
      else
        value = tostring(cell)
      end

      local padding = string.rep(" ", widths[col] - #value)
      local display_value = value .. padding

      table.insert(row_line, display_value)

      if hl_group then
        local start_col = current_col_position
        local end_col = start_col + #display_value

        table.insert(extmarks, {
          row = row_index,
          start_col = start_col,
          end_col = end_col,
          hl_group = hl_group,
        })
      end

      current_col_position = current_col_position + #display_value
    end
    table.insert(tbl, table.concat(row_line, ""))
  end

  return tbl, extmarks
end

function M.is_selected(row, selections)
  if not selections or #selections == 0 then
    return false
  end
  for _, selection in ipairs(selections) do
    local is_selected = true
    for key, value in pairs(selection) do
      if row[key] ~= value then
        is_selected = false
      end
    end
    if is_selected then
      return true
    end
  end
  return false
end

--- Get visible headers accounting for column order and visibility
---@param resource string Resource name
---@param original_headers string[] Original headers from definition
---@return string[] visible_headers
function M.getVisibleHeaders(resource, original_headers)
  local headers = original_headers

  -- Reorder based on saved column order
  local saved_order = state.column_order[resource]
  if saved_order and #saved_order > 0 then
    local header_set = {}
    for _, h in ipairs(headers) do
      header_set[h] = true
    end
    local ordered = {}
    local used = {}
    for _, h in ipairs(saved_order) do
      if header_set[h] then
        table.insert(ordered, h)
        used[h] = true
      end
    end
    for _, h in ipairs(headers) do
      if not used[h] then
        table.insert(ordered, h)
      end
    end
    headers = ordered
  end

  -- Filter based on visibility
  local visible = {}
  local visibility = state.column_visibility[resource]
  for _, header in ipairs(headers) do
    if M.required_headers[header] or not visibility or visibility[header] ~= false then
      table.insert(visible, header)
    end
  end

  return visible
end

--- Get column indices for NAME and NAMESPACE based on visible headers
---@param resource string Resource name
---@param original_headers string[] Original headers from definition
---@return number|nil name_col Index of NAME column (1-based)
---@return number|nil ns_col Index of NAMESPACE column (1-based), nil if not visible
function M.getColumnIndices(resource, original_headers)
  local visible = M.getVisibleHeaders(resource, original_headers)
  return M.find_index(visible, "NAME"), M.find_index(visible, "NAMESPACE")
end

--- Get the current selection from the buffer
---@vararg number
---@return string|nil ...
function M.getCurrentSelection(...)
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = state.get_buffer_state(bufnr)
  if not buf_state or not buf_state.content_row_start then
    return nil
  end

  local line_number = vim.api.nvim_win_get_cursor(0)[1]
  if line_number <= buf_state.content_row_start then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  local columns = vim.split(line, "%s%s+")

  local results = {}
  local indices = { ... }
  for i = 1, #indices do
    local index = indices[i]
    local col_value = columns[index]
    if not col_value then
      return nil
    end
    local trimmed = vim.trim(col_value)
    table.insert(results, trimmed)
  end

  return unpack(results)
end

function M.find_index(haystack, needle)
  if haystack then
    for index, value in ipairs(haystack) do
      if value == needle then
        return index
      end
    end
  end
  return nil -- Return nil if the needle is not found
end

function M.find_resource(data, name, namespace)
  if data.items then
    return vim.iter(data.items):find(function(row)
      return row.metadata.name == name and (namespace and row.metadata.namespace == namespace or true)
    end)
  end
  if data.rows then
    return vim.iter(data.rows):find(function(row)
      return row.object.metadata.name == name and (namespace and row.object.metadata.namespace == namespace or true)
    end).object
  end
  if data then
    return vim.iter(data):find(function(row)
      if row.metadata then
        return row.metadata.name == name and (row.metadata.namespace == namespace or true)
      else
        return row.name == name and (row.namespace == namespace or true)
      end
    end)
  end
  return nil
end

--- Check if a table is empty
---@param table table
---@return boolean
function M.isEmpty(table)
  return next(table) == nil
end

return M
