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

function M.get_plug_mappings(headers, mode)
  local keymaps_table = {}
  local header_lookup = {}

  if not headers then
    return keymaps_table
  end

  local keymaps = vim.tbl_extend("force", vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(0, mode))
  for _, header in ipairs(headers) do
    header_lookup[header.key] = { desc = header.desc, long_desc = header.long_desc }
  end

  -- Iterate over keymaps and check if they match any header key
  for _, keymap in ipairs(keymaps) do
    local header = header_lookup[keymap.rhs]
    if header then
      table.insert(keymaps_table, { key = keymap.lhs, desc = header.desc, long_desc = header.long_desc })
    end
  end
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

  local keymaps_normal = M.get_plug_mappings(headers, "n")
  local keymaps_insert = M.get_plug_mappings(headers, "i")
  local keymaps = vim.tbl_extend("force", keymaps_normal, keymaps_insert)
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

--- Add context rows to the hints and marks tables
---@param context table
---@param hints table[]
---@param marks table[]
local function addContextRows(context, hints, marks)
  if context.contexts then
    local desc, context_info = "Context:   ", context.contexts[1].context
    local line = desc .. context_info.cluster .. " │ User:    " .. context_info.user .. "\n"

    M.add_mark(marks, #hints, #desc, #desc + #context_info.cluster, hl.symbols.pending)
    table.insert(hints, line)
  end
  local desc, namespace = "Namespace: ", state.getNamespace()
  local line = desc .. namespace
  if context.clusters then
    if context.contexts then
      line = line .. string.rep(" ", #context.contexts[1].context.cluster - #namespace)
    end
    line = line .. " │ " .. "Cluster: " .. context.clusters[1].name
    if state.livez.ok then
      line = line .. " ✅"
    else
      local current_time = os.time()
      local time_since = os.difftime(current_time, state.livez.time_of_ok)
      line = line .. " ⚠️" .. " (" .. time_since .. "s)"
    end
  end

  M.add_mark(marks, #hints, #desc, #desc + #namespace, hl.symbols.pending)
  table.insert(hints, line .. "\n")
end

--- Add divider row
---@param divider { resource: string, count: string, filter: string }|nil
---@param hints table[]
---@param marks table[]
local function addDividerRow(divider, hints, marks)
  -- Add separator row
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local text_width = win_width - vim.fn.getwininfo(win)[1].textoff
  local half_width = math.floor(text_width / 2)
  local row = " "
  if divider then
    local resource = divider.resource or ""
    local count = divider.count or ""
    local filter = divider.filter or ""
    local info = resource .. count .. filter
    local padding = string.rep("-", half_width - math.floor(#info / 2))

    local virt_text = {
      { padding, hl.symbols.success },
      { " " .. resource, hl.symbols.header },
      { "[", hl.symbols.header },
      { count },
      { "]", hl.symbols.header },
    }

    if filter ~= "" then
      table.insert(virt_text, { " </", hl.symbols.header })
      table.insert(virt_text, { filter, hl.symbols.pending })
      table.insert(virt_text, { ">", hl.symbols.header })
    end
    table.insert(virt_text, { " " .. padding, hl.symbols.success })

    table.insert(marks, {
      row = #hints,
      start_col = 0,
      virt_text = virt_text,
      virt_text_pos = "overlay",
    })
  else
    local padding = string.rep("-", half_width)
    row = padding .. padding
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
  end

  table.insert(hints, row)
end
--- Generate header hints and marks
---@param headers table[]
---@param include_defaults boolean
---@param include_context boolean
---@param divider { resource: string, count: string, filter: string }|nil
---@return table[], table[]
function M.generateHeader(headers, include_defaults, include_context, divider)
  local hints = {}
  local marks = {}

  if include_defaults then
    local defaults = {
      { key = "<Plug>(kubectl.refresh)", desc = "reload" },
      { key = "<Plug>(kubectl.alias_view)", desc = "aliases" },
      { key = "<Plug>(kubectl.filter_view)", desc = "filter" },
      { key = "<Plug>(kubectl.namespace_view)", desc = "namespace" },
      { key = "<Plug>(kubectl.help)", desc = "help" },
    }
    for _, default in ipairs(defaults) do
      table.insert(headers, default)
    end
  end

  -- Add hints rows
  if config.options.hints then
    addHeaderRow(headers, hints, marks)
    table.insert(hints, "\n")
  end

  -- Add context rows
  if include_context and config.options.context then
    local context = state.getContext()
    if context then
      addContextRows(context, hints, marks)
    end
  end

  addDividerRow(divider, hints, marks)

  return vim.split(table.concat(hints, ""), "\n"), marks
end

--- Pretty print data in a table format
---@param data table[]
---@param headers string[]
---@return table[], table[]
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

  -- Create table rows
  for row_index, row in ipairs(data) do
    local row_line = {}
    local current_col_position = 0

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
