local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local string_util = require("kubectl.utils.string")
local M = {}

-- Function to calculate column widths
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
function M.add_mark(extmarks, row, start_col, end_col, hl_group)
  table.insert(extmarks, { row = row, start_col = start_col, end_col = end_col, hl_group = hl_group })
end

local function addHeaderRow(headers, hints, marks)
  local hint_line = "Hint: "
  local length = #hint_line
  M.add_mark(marks, #hints, 0, length, hl.symbols.success)

  for index, hintConfig in ipairs(headers) do
    length = #hint_line
    hint_line = hint_line .. hintConfig.key .. " " .. hintConfig.desc
    if index < #headers then
      hint_line = hint_line .. " | "
    end
    M.add_mark(marks, #hints, length, length + #hintConfig.key, hl.symbols.pending)
  end

  table.insert(hints, hint_line .. "\n")
end

local function addContextRows(context, hints, marks)
  if context.clusters then
    local line = "Cluster:   " .. context.clusters[1].name .. "\n"
    table.insert(hints, line)
  end
  if context.contexts then
    local desc, context_info = "Context:   ", context.contexts[1].context
    local line = desc .. context_info.cluster
    M.add_mark(marks, #hints, #desc, #line, hl.symbols.pending)
    table.insert(hints, line .. "\n")

    line = "User:      " .. context_info.user .. "\n"
    table.insert(hints, line)
  end
  local desc, namespace = "Namespace: ", state.getNamespace()
  local line = desc .. namespace
  M.add_mark(marks, #hints, #desc, #line, hl.symbols.pending)
  table.insert(hints, line .. "\n")
end

function M.generateHeader(headers, include_defaults, include_context)
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
    local divider = string.rep("―", vim.api.nvim_win_get_width(win))
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

function M.getCurrentSelection(...)
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

function M.isEmpty(table)
  for _ in pairs(table) do
    return false
  end
  return true
end

return M
