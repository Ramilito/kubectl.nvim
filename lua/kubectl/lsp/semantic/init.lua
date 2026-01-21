local hl = require("kubectl.actions.highlight")

local M = {}

local semantic_enabled = true

-- Symbol to semantic highlight mapping
local symbol_to_semantic = {
  KubectlError = hl.symbols.semantic_error,
  KubectlWarning = hl.symbols.semantic_warn,
}

-- Completed status values (dimmed, not attention-grabbing)
local completed_values = {
  Completed = true,
  Succeeded = true,
}

--- Get semantic highlight for a row based on symbol (fast path)
---@param row table
---@return string|nil
local function get_row_highlight(row)
  -- Check status symbol first (most common case)
  if row.status and type(row.status) == "table" then
    local semantic = symbol_to_semantic[row.status.symbol]
    if semantic then
      return semantic
    end
    -- Check for completed values (dimmed background)
    if row.status.value and completed_values[row.status.value] then
      return hl.symbols.semantic_completed
    end
  end

  -- Check phase symbol
  if row.phase and type(row.phase) == "table" then
    local semantic = symbol_to_semantic[row.phase.symbol]
    if semantic then
      return semantic
    end
    if row.phase.value and completed_values[row.phase.value] then
      return hl.symbols.semantic_completed
    end
  end

  -- Check conditions symbol
  if row.conditions and type(row.conditions) == "table" then
    local semantic = symbol_to_semantic[row.conditions.symbol]
    if semantic then
      return semantic
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
        priority = 10, -- Lower priority so selection highlights can override
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
