local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local time = require("kubectl.utils.time")
local M = {}

--- Calculate column widths for table data
---@param rows table[]
---@param columns string[]
---@return table
local function calculate_column_widths(rows, columns)
  local widths = {}
  for _, row in ipairs(rows) do
    for _, column in pairs(columns) do
      if type(row[column]) == "table" then
        widths[column] = math.max(widths[column] or 0, vim.fn.strdisplaywidth(tostring(row[column].value)))
      else
        widths[column] = math.max(widths[column] or 0, vim.fn.strdisplaywidth(tostring(row[column])))
      end
    end
  end

  return widths
end

--- Calculate and distribute extra padding
---@param widths table The table of current column widths
---@param headers string[] The column headers
local function calculate_extra_padding(widths, headers)
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local textoff = vim.fn.getwininfo(win)[1].textoff
  local text_width = win_width - textoff
  local total_width = 0
  local separator_width = 3 -- Padding for sort icon or column separator
  local column_count = #headers

  -- Calculate the maximum width for each column, including separator width
  for index, key in ipairs(headers) do
    local value_width = widths[string.lower(key)] or 0
    local header_width = #key
    local max_width = math.max(header_width, value_width) + separator_width
    if index == #headers then
      max_width = max_width - separator_width + 1
    end
    widths[string.lower(key)] = max_width
    total_width = total_width + max_width
  end

  -- Calculate total padding needed (subtracting 2 for any additional offsets, not sure why this is needed tbh)
  local total_padding = text_width - total_width - 2

  if total_padding < 0 then
    -- Not enough space to add extra padding
    return
  end

  -- Exclude the last column from receiving extra padding
  local padding_columns = column_count - 1

  if padding_columns > 0 then
    -- Calculate base padding and distribute any remainder
    local base_padding = math.floor(total_padding / padding_columns)
    local extra_padding = total_padding % padding_columns

    -- Add padding to each column except the last one
    for i, key in ipairs(headers) do
      if i == column_count then
        -- Do not add extra padding to the last column
        break
      end
      local extra = (i <= extra_padding) and 1 or 0
      widths[string.lower(key)] = widths[string.lower(key)] + base_padding + extra
    end
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
    header_lookup[header.key] = { desc = header.desc, long_desc = header.long_desc, sort_order = header.sort_order }
  end

  -- Iterate over keymaps and check if they match any header key
  for _, keymap in ipairs(keymaps) do
    local header = header_lookup[keymap.rhs]
    if header then
      table.insert(
        keymaps_table,
        { key = keymap.lhs, desc = header.desc, long_desc = header.long_desc, sort_order = header.sort_order }
      )
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

--- Add a header row to the hints and marks tables
---@param headers table[]
---@param hints table[]
---@param marks table[]
local function addHeaderRow(headers, hints, marks)
  local hint_line = "Hints: "
  local length = #hint_line
  M.add_mark(marks, #hints, 0, length, hl.symbols.success)

  local keymaps = M.get_plug_mappings(headers)
  for index, map in ipairs(keymaps) do
    length = #hint_line
    hint_line = hint_line .. map.key .. " " .. map.desc
    if index < #keymaps then
      local divider = " | "
      hint_line = hint_line .. divider
      M.add_mark(marks, #hints, #hint_line - #divider, #hint_line, hl.symbols.success)
    end
    M.add_mark(marks, #hints, length, length + #map.key, hl.symbols.pending)
  end

  table.insert(hints, hint_line .. "\n")
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

---@param divider { resource: string, count: string, filter: string }|nil
---@return string The formatted divider row
function M.generateDivider(divider)
  local win = vim.api.nvim_get_current_win()
  local text_width = vim.api.nvim_win_get_width(win)

  if not divider then
    return ("%#KubectlSuccess#%s%%*"):format(string.rep("-", text_width))
  end

  local resource = divider.resource or ""
  local count = divider.count or ""
  local filter = divider.filter or ""
  local selected_count = vim.tbl_count(state.getSelections())

  if selected_count > 0 then
    count = ("%d/%s"):format(selected_count, count)
  end

  local center_text = table.concat({
    "%#KubectlHeader#",
    " ",
    resource,
    " [",
    count,
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

  if include_defaults then
    local defaults = {
      { key = "<Plug>(kubectl.refresh)", desc = "reload" },
      { key = "<Plug>(kubectl.alias_view)", desc = "aliases" },
      { key = "<Plug>(kubectl.filter_view)", desc = "filter" },
      { key = "<Plug>(kubectl.namespace_view)", desc = "namespace" },
      { key = "<Plug>(kubectl.help)", desc = "help", sort_order = 100 },
    }
    for _, default in ipairs(defaults) do
      table.insert(headers, default)
    end
  end

  if not config.options.headers then
    return vim.split(table.concat(hints, ""), "\n"), marks
  end

  -- Add hints rows
  if config.options.hints then
    addHeaderRow(headers, hints, marks)
    table.insert(hints, "\n")
  end

  local items = {}

  -- Add context rows
  if include_context and config.options.context then
    local context = state.getContext()
    if context then
      vim.list_extend(items, addContextRows(context))
    end
  end

  -- Add versions
  if include_context and config.options.skew.enabled then
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
  if include_context and config.options.heartbeat then
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
---@return table, table
function M.pretty_print(data, headers, sort_by)
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

  calculate_extra_padding(widths, headers)
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

  local selections = state.selections
  -- Create table rows
  for row_index, row in ipairs(data) do
    local is_selected = M.is_selected(row, selections)
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
        sign_text = ">>",
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

--- Get the current selection from the buffer
---@vararg number
---@return string|nil
function M.getCurrentSelection(...)
  local line_number = vim.api.nvim_win_get_cursor(0)[1]
  if line_number <= state.content_row_start then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  local columns = vim.split(line, "%s%s+")

  local results = {}
  local indices = { ... }
  for i = 1, #indices do
    local index = indices[i]
    local trimmed = vim.trim(columns[index])
    table.insert(results, trimmed)
  end

  return unpack(results)
end

function M.find_index(haystack, needle)
  for index, value in ipairs(haystack) do
    if value == needle then
      return index
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
  return nil
end

--- Check if a table is empty
---@param table table
---@return boolean
function M.isEmpty(table)
  return next(table) == nil
end

return M
