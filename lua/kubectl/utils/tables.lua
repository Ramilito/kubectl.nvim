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

function M.generateHints(hintConfigs, include_defaults, include_context)
  local hints = {}
  local extmarks = {}

  if include_defaults then
    local defaults = {
      { key = "<R>", desc = "reload" },
      { key = "<C-f>", desc = "filter" },
      { key = "<C-n>", desc = "namespace" },
      { key = "<g?>", desc = "help" },
    }
    for _, default in ipairs(defaults) do
      table.insert(hintConfigs, default)
    end
  end

  if config.options.hints then
    local hint_line = "Hint: "
    local length = #hint_line
    table.insert(extmarks, { row = 0, start_col = 0, end_col = #hint_line, hl_group = hl.symbols.success })
    for index, hintConfig in ipairs(hintConfigs) do
      length = #hint_line
      hint_line = hint_line .. hintConfig.key .. " " .. hintConfig.desc
      if index < #hintConfigs then
        hint_line = hint_line .. " | "
      end
      table.insert(extmarks, { row = 0, start_col = length, end_col = length + #hintConfig.key, hl_group = hl.symbols.pending })
    end

    table.insert(hints, hint_line .. "\n\n")
  end

  if include_context and config.options.context then
    local hint = ""

    local context = state.getContext()
    if context then
      if context.cluster then
        hint = hint .. "Cluster:   " .. context.clusters[1].name .. "\n"
      end
      if context.contexts then
        hint = hint .. "Context:   " .. context.contexts[1].context.cluster .. "\n"

        table.insert(extmarks, {
          row = #hints + 1,
          start_col = #hint - #context.contexts[1].context.cluster - 1,
          end_col = #hint,
          hl_group = hl.symbols.pending,
        })
        hint = hint .. "User:      " .. context.contexts[1].context.user .. "\n"
      end
      hint = hint .. "Namespace: " .. hl.symbols.pending .. state.getNamespace() .. hl.symbols.clear .. "\n"
      table.insert(hints, hint)
    end
  end

  if #hints > 0 then
    local win = vim.api.nvim_get_current_win()
    table.insert(hints, string.rep("―", vim.api.nvim_win_get_width(win)))
  end

  return vim.split(table.concat(hints, ""), "\n"), extmarks
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
