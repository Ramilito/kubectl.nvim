local events = require("kubectl.utils.events")

local M = {}

local semantic_enabled = true

--- Extract value from field (handles both table and string)
---@param field any
---@return string|nil
local function get_value(field)
  if type(field) == "table" then
    return field.value
  elseif type(field) == "string" then
    return field
  end
  return nil
end

--- Get semantic highlight for a row
---@param row table
---@return string|nil
local function get_row_highlight(row)
  -- Check status field
  local status = get_value(row.status)
  if status then
    local hl = events.GetSemanticHighlight(status)
    if hl then
      return hl
    end
  end

  -- Check phase field
  local phase = get_value(row.phase)
  if phase then
    local hl = events.GetSemanticHighlight(phase)
    if hl then
      return hl
    end
  end

  return nil
end

--- Add semantic line highlights to extmarks
---@param data table[] Processed data rows
---@param extmarks table[] Existing extmarks to append to
---@param content_start number Row offset for content (1 for header row)
function M.add_line_highlights(data, extmarks, content_start)
  if not semantic_enabled or not data or not extmarks then
    return
  end

  content_start = content_start or 1

  for i, row in ipairs(data) do
    local hl_group = get_row_highlight(row)
    if hl_group then
      table.insert(extmarks, {
        row = content_start + i - 1,
        start_col = 0,
        line_hl_group = hl_group,
      })
    end
  end
end

--- Toggle semantic highlighting
function M.toggle()
  semantic_enabled = not semantic_enabled
  if semantic_enabled then
    vim.notify("Semantic highlighting: on", vim.log.levels.INFO)
  else
    vim.notify("Semantic highlighting: off", vim.log.levels.INFO)
  end

  local views = require("kubectl.views")
  views.Redraw()
end

--- Check if semantic highlighting is enabled
---@return boolean
function M.is_enabled()
  return semantic_enabled
end

return M
