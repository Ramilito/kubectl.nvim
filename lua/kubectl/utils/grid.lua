local hl = require("kubectl.actions.highlight")
local M = {}

local function calculate_extra_padding(widths, headers)
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local text_width = win_width - vim.fn.getwininfo(win)[1].textoff
  local total_width = 0

  for key, value in pairs(widths) do
    local max_width = math.max(#key, value)
    total_width = total_width + max_width
    widths[key] = max_width
  end
  return math.floor(math.max((text_width - total_width) / #headers - 1, 0))
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
  return str .. string.rep(" ", width - #str + 4)
end

function M.pretty_print(data, sections)
  local layout = {}
  local extmarks = {}
  local max_cols = 3
  local max_rows = 0
  local pipe = " ⎪ "
  local dash = "—"

  local widths = section_widths(data, sections)
  local extra_padding = calculate_extra_padding(widths, sections) - 1

  -- Create headers and rows using modulo for dynamic wrapping
  local current_headers = {}
  local rows = {}

  for _, section in ipairs(sections) do
    max_rows = math.max(max_rows, #data[section] or 0)
  end

  for index, section in ipairs(sections) do
    local formatted_section = pad_string(section, (widths[section] + extra_padding))
    table.insert(current_headers, formatted_section)

    for row_index = 1, max_rows do
      local item = data[section][row_index]
      if item then
        local formatted_item =
          pad_string(string.format("%s (%s)", item.name, item.value), (widths[section] + extra_padding) or 10)
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
            value = (rows[row_index].value or "") .. pad_string("", (widths[section] + extra_padding) or 10) .. pipe,
          }
        else
          rows[row_index] = {
            marks = {},
            value = pad_string("", (widths[section] + extra_padding) or 10) .. pipe,
          }
        end
      end
    end

    -- Add headers and rows to the layout when reaching max_cols or last section
    if index % max_cols == 0 or index == #sections then
      local header_row = table.concat(current_headers, pipe)
      table.insert(layout, header_row)
      table.insert(extmarks, { row = #layout - 1, start_col = 0, end_col = #header_row, hl_group = hl.symbols.header })
      table.insert(layout, "")
      table.insert(extmarks, {
        row = #layout - 1,
        start_col = 0,
        virt_text = { { string.rep(dash, #header_row + extra_padding), hl.symbols.success } },
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
      table.insert(layout, "") -- Add an empty line between groups
    end
  end
  return layout, extmarks
end

return M
