local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
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

local function generateHintLine(key, desc)
  return hl.symbols.pending .. key .. " " .. hl.symbols.clear .. desc .. " | "
end

function M.generateContext()
  local hint = ""

  if KUBE_CONFIG then
    hint = hint .. "Cluster:   " .. KUBE_CONFIG.clusters[1].name .. "\n"
    hint = hint .. "Context:   " .. KUBE_CONFIG.contexts[1].context.cluster .. "\n"
    hint = hint .. "User:      " .. KUBE_CONFIG.contexts[1].context.user .. "\n"
    hint = hint .. "Namespace: " .. NAMESPACE .. "\n"
    return hint
  end
end

function M.generateHints(hintConfigs, include_defaults, include_context)
  local hints = {}

  if config.options.hints then
    local hint_line = hl.symbols.success .. "Hint: " .. hl.symbols.clear
    for _, hintConfig in ipairs(hintConfigs) do
      hint_line = hint_line .. generateHintLine(hintConfig.key, hintConfig.desc)
    end

    if include_defaults then
      hint_line = hint_line .. generateHintLine("<R>", "reload")
      hint_line = hint_line .. generateHintLine("<C-f>", "filter")
      hint_line = hint_line .. generateHintLine("<C-n>", "namespace")
      hint_line = hint_line .. generateHintLine("<g?>", "help"):gsub(" | $", "") -- remove the last separator
    end

    table.insert(hints, hint_line .. "\n\n")
  end

  if include_context and config.options.context then
    table.insert(hints, M.generateContext())
  end

  if #hints > 0 then
    local win = vim.api.nvim_get_current_win()
    table.insert(hints, string.rep("―", vim.api.nvim_win_get_width(win)))
  end

  return vim.split(table.concat(hints, ""), "\n")
end

-- Function to print the table
function M.pretty_print(data, headers)
  local columns = {}
  for k, v in ipairs(headers) do
    columns[k] = v:lower()
  end

  local widths = calculate_column_widths(data, columns)
  for key, value in pairs(widths) do
    widths[key] = math.max(#key, value)
  end

  local tbl = ""

  -- Create table header
  for i, header in pairs(headers) do
    local column_width = widths[columns[i]] or 10
    tbl = tbl .. hl.symbols.header .. header .. hl.symbols.clear .. "  " .. string.rep(" ", column_width - #header + 1)
  end
  tbl = tbl .. "\n"

  -- Create table rows
  for _, row in ipairs(data) do
    for _, col in ipairs(columns) do
      if type(row[col]) == "table" then
        local value = tostring(row[col].value)
        tbl = tbl .. row[col].symbol .. value .. hl.symbols.clear .. "  " .. string.rep(" ", widths[col] - #value + 1)
      else
        local value = tostring(row[col])
        tbl = tbl .. value .. hl.symbols.tab .. "  " .. string.rep(" ", widths[col] - #value + 1)
      end
    end
    tbl = tbl .. "\n"
  end

  return vim.split(tbl, "\n")
end

function M.getCurrentSelection(...)
  local line = vim.api.nvim_get_current_line()
  local columns = vim.split(line, hl.symbols.tab)

  local results = {}
  local indices = { ... }
  for i = 1, #indices do
    local index = indices[i]
    local trimmed = string_util.trim(columns[index])
    table.insert(results, trimmed)
  end

  return unpack(results) -- Use unpack instead of table.unpack for Lua 5.1 compatibility
end

return M
