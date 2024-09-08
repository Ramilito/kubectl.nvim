local M = {}

local function section_widths(rows, sections)
  local widths = {}

  for _, section in ipairs(sections) do
    for _, row in pairs(rows[section]) do
      if row.name and row.value then
        widths[section] = math.max(widths[section] or 0, #tostring(row.name .. " " .. row.value))
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
  local max_cols = 3
  local pipe = " │ "
  local dash = "—"

  local widths = section_widths(data, sections)

  -- Create headers and rows using modulo for dynamic wrapping
  local current_headers = {}
  local current_rows = {}

  for index, section in ipairs(sections) do
    local formatted_section = pad_string(section, widths[section])
    table.insert(current_headers, formatted_section)

    local max_rows = #data[section] or 0

    for row_index = 1, max_rows do
      local item = data[section][row_index]
      if item then
        local formatted_item = pad_string(string.format("%s (%s)", item.name, item.value), widths[section] or 10)
        current_rows[row_index] = (current_rows[row_index] or "") .. formatted_item .. pipe
      else
        current_rows[row_index] = (current_rows[row_index] or "") .. pad_string("", widths[section] or 10) .. pipe
      end
    end

    -- When index is a multiple of 3, or it's the last section, add the headers and rows to the layout
    if index % max_cols == 0 or index == #sections then
      -- Combine and insert headers
      local header_row = table.concat(current_headers, pipe)
      local divider_row = string.rep(dash, #header_row)
      table.insert(layout, header_row)
      table.insert(layout, divider_row)

      -- Insert the rows for the current group
      for _, row in ipairs(current_rows) do
        table.insert(layout, row)
      end

      -- Clear current headers and rows for the next group
      current_headers = {}
      current_rows = {}
      table.insert(layout, "") -- Add an empty line between groups
    end
  end

  return layout
end

return M
