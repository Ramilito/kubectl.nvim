local hl = require("kubectl.actions.highlight")
local M = {}

local function calculate_extra_padding(columns, widths)
  if not columns or not widths then
    return 0
  end
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local textoff = vim.fn.getwininfo(win)[1].textoff
  local text_width = win_width - textoff
  local total_width = 0
  local separator_width = 0 -- Padding for sort icon or column separator

  for _, key in ipairs(columns) do
    local value_width = widths[string.lower(key)] or 0
    local max_width = math.max(#key, value_width) + separator_width
    widths[string.lower(key)] = max_width
    total_width = total_width + max_width
  end

  local total_padding = text_width - total_width

  if total_padding < 0 then
    -- Not enough space to add extra padding
    return
  end

  -- Calculate base padding and distribute any remainder, also remove the pipe character
  local base_padding = math.floor(total_padding / #columns) - 3
  local extra_padding = total_padding % #columns

  for i, key in ipairs(columns) do
    local additional_padding = base_padding
    if i <= extra_padding then
      additional_padding = additional_padding + 1
    end
    widths[string.lower(key)] = widths[string.lower(key)] + additional_padding
  end
end

local function section_widths(rows, sections)
  local widths = {}

  for _, section in ipairs(sections) do
    for _, row in ipairs(rows[section] or {}) do
      if row.name and row.value then
        local length = #row.name + #row.value + 1 -- 1 for the space between
        widths[section] = math.max(widths[section] or 0, length)
      end
    end
  end

  return widths
end

local function pad_string(str, width)
  return str .. string.rep(" ", width - #str)
end

function M.pretty_print(data, sections)
  if not data then
    return {}, {}
  end
  local layout = {}
  local extmarks = {}
  local max_cols = 2
  local max_items = 0
  local pipe = " ⎪ "
  local dash = "―"

  local widths = section_widths(data, sections)
  -- Create headers and rows using modulo for dynamic wrapping
  local current_headers = {}
  local rows = {}
  local grid = {}
  local row_count = 1

  local columns = {}
  for index, section in ipairs(sections) do
    table.insert(columns, section)
    max_items = math.max(max_items, #data[section] or 0)
    if index % max_cols == 0 or index == #sections then
      calculate_extra_padding(columns, widths)
      grid[row_count] = {
        row = #grid,
        max_items = max_items,
        columns = columns,
      }

      row_count = row_count + 1
      max_items = 0
      columns = {}
    end
  end

  for grid_index, grid_row in ipairs(grid) do
    for _, column in ipairs(grid_row.columns) do
      if not widths[column] then
        break
      end
      local formatted_section = pad_string(column, widths[column])
      table.insert(current_headers, formatted_section)

      for row_index = 1, grid[grid_index].max_items do
        local item = data[column][row_index]
        if item then
          local formatted_item = pad_string(string.format("%s (%s)", item.name, item.value), widths[column] or 0)
          local row = rows[row_index] and rows[row_index].value or ""

          rows[row_index] = {
            value = (row or "") .. formatted_item .. pipe,
            marks = rows[row_index] and rows[row_index].marks or {},
          }

          local start_col = #rows[row_index].value - #formatted_item - #pipe
          table.insert(rows[row_index].marks, {
            value = item.name,
            hl_group = hl.symbols.note,
            start_col = start_col,
            end_col = start_col + #item.name,
          })
          table.insert(rows[row_index].marks, {
            value = item.value,
            hl_group = item.symbol,
            start_col = start_col + #item.name,
            end_col = #rows[row_index].value - #pipe,
          })
        else
          local row = rows[row_index]
          if row then
            rows[row_index] = {
              marks = rows[row_index].marks,
              value = (rows[row_index].value or "") .. pad_string("", widths[column] or 0) .. pipe,
            }
          else
            rows[row_index] = {
              marks = {},
              value = pad_string("", widths[column] or 0) .. pipe,
            }
          end
        end
      end
    end
    local header_row = table.concat(current_headers, pipe)

    table.insert(layout, "")
    table.insert(extmarks, {
      row = #layout - 1,
      start_col = 0,
      virt_text = { { string.rep(dash, #header_row), hl.symbols.success } },
      virt_text_pos = "overlay",
    })
    table.insert(layout, header_row)
    table.insert(extmarks, { row = #layout - 1, start_col = 0, end_col = #header_row, hl_group = hl.symbols.header })
    table.insert(layout, "")
    table.insert(extmarks, {
      row = #layout - 1,
      start_col = 0,
      virt_text = { { string.rep(dash, #header_row), hl.symbols.success } },
      virt_text_pos = "overlay",
    })

    -- Insert rows
    for _, row in ipairs(rows) do
      table.insert(layout, row.value)
      for _, mark in ipairs(row.marks) do
        table.insert(
          extmarks,
          { row = #layout - 1, start_col = mark.start_col, end_col = mark.end_col, hl_group = mark.hl_group }
        )
      end
    end

    -- Reset for the next group
    current_headers = {}
    rows = {}
    row_count = row_count + 1
    table.insert(layout, "") -- Add an empty line between groups
  end

  return layout, extmarks
end

return M
