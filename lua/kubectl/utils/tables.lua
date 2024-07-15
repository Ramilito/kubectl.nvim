local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local string_util = require("kubectl.utils.string")
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
        widths[column] = math.max(widths[column] or 0, #tostring(row[column].value))
      else
        widths[column] = math.max(widths[column] or 0, #tostring(row[column]))
      end
    end
  end

  return widths
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
  local hint_line = "Hint: "
  local length = #hint_line
  M.add_mark(marks, #hints, 0, length, hl.symbols.success)

  for index, hintConfig in ipairs(headers) do
    length = #hint_line
    hint_line = hint_line .. hintConfig.key .. " " .. hintConfig.desc
    if index < #headers then
      local divider = " | "
      hint_line = hint_line .. divider
      M.add_mark(marks, #hints, #hint_line - #divider, #hint_line, hl.symbols.success)
    end
    M.add_mark(marks, #hints, length, length + #hintConfig.key, hl.symbols.pending)
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
    line = line .. string.rep(" ", #context.contexts[1].context.cluster - #namespace)
    line = line .. " │ " .. "Cluster: " .. context.clusters[1].name
  end

  M.add_mark(marks, #hints, #desc, #desc + #namespace, hl.symbols.pending)
  table.insert(hints, line .. "\n")
end

--- Generate header hints and marks
---@param headers table[]
---@param include_defaults boolean
---@param include_context boolean
---@param divider_text string
---@return table[], table[]
function M.generateHeader(headers, include_defaults, include_context, divider_text)
  local hints = {}
  local marks = {}

  if include_defaults then
    local defaults = {
      { key = "<R>", desc = "reload" },
      { key = "<C-f>", desc = "filter" },
      { key = "<C-n>", desc = "namespace" },
      { key = "<g?>", desc = "help" },
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

  -- Add separator row
  if #hints > 0 then
    local win = vim.api.nvim_get_current_win()
    local win_width = vim.api.nvim_win_get_width(win)
    local divider = ""
    if divider_text then
      local half_width = math.floor((win_width - #divider_text) / 2)
      divider = string.rep("―", half_width)
        .. " "
        .. string_util.capitalize(divider_text)
        .. " "
        .. string.rep("―", half_width)
    else
      divider = string.rep("―", win_width)
    end

    table.insert(marks, {
      row = #hints,
      start_col = 0,
      virt_text = { { divider, hl.symbols.success } },
      virt_text_pos = "overlay",
    })
  end

  if #hints > 0 then
    return vim.split(table.concat(hints, ""), "\n"), marks
  end
  return hints, marks
end

--- Pretty print data in a table format
---@param data table[]
---@param headers string[]
---@return table[], table[]
function M.pretty_print(data, headers)
  local columns = {}
  for k, v in ipairs(headers) do
    columns[k] = v:lower()
  end

  local widths = calculate_column_widths(data, columns)
  for key, value in pairs(widths) do
    widths[key] = math.max(#key, value)
  end

  local tbl = {}
  local extmarks = {}

  -- Create table header
  local header_line = {}
  for i, header in ipairs(headers) do
    local column_width = widths[columns[i]] or 10
    local value = header .. "  " .. string.rep(" ", column_width - #header + 1)
    table.insert(header_line, value)

    M.add_mark(extmarks, 0, #table.concat(header_line, "") - #value, #table.concat(header_line, ""), hl.symbols.header)
  end
  table.insert(tbl, table.concat(header_line, ""))

  -- Create table rows
  for row_index, row in ipairs(data) do
    local row_line = {}
    for _, col in ipairs(columns) do
      local value
      local hl_group
      if type(row[col]) == "table" then
        value = tostring(row[col].value)
        hl_group = row[col].symbol
      else
        value = tostring(row[col])
        hl_group = nil
      end

      local display_value = value .. "  " .. string.rep(" ", widths[col] - #value + 1)
      table.insert(row_line, display_value)

      if hl_group then
        table.insert(extmarks, {
          row = row_index,
          start_col = #table.concat(row_line, "") - #display_value,
          end_col = #table.concat(row_line, ""),
          hl_group = hl_group,
        })
      end
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
    local trimmed = string_util.trim(columns[index])
    table.insert(results, trimmed)
  end

  return unpack(results)
end

--- Check if a table is empty
---@param table table
---@return boolean
function M.isEmpty(table)
  return next(table) == nil
end

return M
