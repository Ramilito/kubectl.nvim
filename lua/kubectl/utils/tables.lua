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

function M.generateHintLine(key, desc, includePipe)
  local line = hl.symbols.pending .. key .. " " .. hl.symbols.clear .. desc
  if includePipe then
    line = line .. " | "
  end
  return line
end

function M.generateContext()
  local hint = ""

  local context = state.getContext()
  if context then
    if context.cluster then
      hint = hint .. "Cluster:   " .. context.clusters[1].name .. "\n"
    end
    if context.contexts then
      hint = hint .. "Context:   " .. hl.symbols.pending .. context.contexts[1].context.cluster .. hl.symbols.clear .. "\n"
      hint = hint .. "User:      " .. context.contexts[1].context.user .. "\n"
    end
    hint = hint .. "Namespace: " .. hl.symbols.pending .. state.getNamespace() .. hl.symbols.clear .. "\n"
    return hint
  end
end

function M.generateHints(hintConfigs, include_defaults, include_context)
  local hints = {}

  if config.options.hints then
    local hint_line = hl.symbols.success .. "Hint: " .. hl.symbols.clear
    for _, hintConfig in ipairs(hintConfigs) do
      hint_line = hint_line .. M.generateHintLine(hintConfig.key, hintConfig.desc, true)
    end

    if include_defaults then
      hint_line = hint_line .. M.generateHintLine("<R>", "reload", true)
      hint_line = hint_line .. M.generateHintLine("<C-f>", "filter", true)
      hint_line = hint_line .. M.generateHintLine("<C-n>", "namespace", true)
      hint_line = hint_line .. M.generateHintLine("<g?>", "help")
    end

    table.insert(hints, hint_line .. "\n\n")
  end

  if include_context and config.options.context then
    local contextHints = M.generateContext()
    if contextHints then
      table.insert(hints, M.generateContext())
    end
  end

  if #hints > 0 then
    local win = vim.api.nvim_get_current_win()
    table.insert(hints, string.rep("―", vim.api.nvim_win_get_width(win)))
  end

  return vim.split(table.concat(hints, ""), "\n")
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

    table.insert(extmarks, {
      row = 0,
      start_col = #table.concat(header_line, "") - #value,
      end_col = #table.concat(header_line, ""),
      hl_group = hl.symbols.header,
    })
  end
  table.insert(tbl, table.concat(header_line, ""))

  -- Create table rows
  for row_index, row in ipairs(data) do
    local row_line = {}
    for col_index, col in ipairs(columns) do
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
