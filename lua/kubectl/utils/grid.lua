local M = {}

local function add_rows_to_sections(grid, sections, data)
  for _, section in pairs(sections) do
    local row = ""
    for _, value in pairs(data[section]) do
      if value.name and value.value then
        row = row .. value.name .. " " .. value.value .. " "
      end
    end
    table.insert(grid, row)
  end
end

local function add_sections(grid, sections, grid_size, data, widths)
  local row = ""
  local headers = {}
  local padding = ""

  for i, section in ipairs(sections) do
    local width = widths[section] or 0
    padding = padding .. string.rep(" ", width - #section)
    row = row .. "---- " .. section .. " ---- " .. padding
    table.insert(headers, section)

    if i % grid_size == 0 or i == #sections then
      table.insert(grid, row)
      add_rows_to_sections(grid, headers, data)

      headers = {}
      row = ""
      padding = ""
    end
  end
end

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

function M.pretty_print(data, sections)
  local grid = {}
  local extmarks = {}
  local grid_size = 3

  local widths = section_widths(data, sections)

  vim.print(widths)
  add_sections(grid, sections, grid_size, data, widths)
  -- for index, value in ipairs(sections) do
  --   if index % grid_size == 0 or index == #sections then
  --   end
  -- end
  return grid, extmarks
end

return M
