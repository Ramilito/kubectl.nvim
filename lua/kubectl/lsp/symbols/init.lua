local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local M = {}

--- Get the resource name from current buffer's filetype
---@return string|nil
local function get_resource_from_buffer()
  local ft = vim.bo.filetype
  if not ft or not ft:match("^k8s_") then
    return nil
  end
  return ft:match("^k8s_(.+)$")
end

--- Extract value from field (handles both table and string)
---@param field any
---@return string
local function get_value(field)
  if type(field) == "table" then
    return field.value or ""
  end
  return field or ""
end

--- Build symbol list from processedData
---@param data table[]
---@param content_start number
---@return table[] symbols
local function build_symbols(data, content_start)
  local symbols = {}

  for i, row in ipairs(data) do
    local name = get_value(row.name)
    local namespace = get_value(row.namespace)
    local status = get_value(row.status)

    if name ~= "" then
      local display = name
      if namespace ~= "" then
        display = namespace .. "/" .. name
      end
      if status ~= "" and status ~= "Running" and status ~= "Active" then
        display = display .. " [" .. status .. "]"
      end

      table.insert(symbols, {
        display = display,
        name = name,
        namespace = namespace,
        line = content_start + i, -- 1-indexed for cursor
      })
    end
  end

  return symbols
end

--- Jump to a resource in the current buffer
function M.jump_to_resource()
  local resource = get_resource_from_buffer()
  if not resource then
    vim.notify("Not in a kubectl resource buffer", vim.log.levels.WARN)
    return
  end

  local builder = manager.get(resource)
  if not builder or not builder.processedData or #builder.processedData == 0 then
    vim.notify("No resources found", vim.log.levels.INFO)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = state.get_buffer_state(bufnr)
  local content_start = buf_state.content_row_start or 1

  local symbols = build_symbols(builder.processedData, content_start)

  if #symbols == 0 then
    vim.notify("No resources found", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, sym in ipairs(symbols) do
    table.insert(items, sym.display)
  end

  vim.ui.select(items, {
    prompt = "Jump to resource:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if choice and idx then
      local sym = symbols[idx]
      vim.api.nvim_win_set_cursor(0, { sym.line, 0 })
      vim.cmd("normal! zz")
    end
  end)
end

return M
