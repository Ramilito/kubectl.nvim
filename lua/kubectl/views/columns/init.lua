local definition = require("kubectl.views.columns.definition")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = definition.definition,
  target_resource = nil,
  target_headers = nil,
}

--- Get checkbox text and highlight for a column
---@param is_required boolean
---@param is_visible boolean
---@return string checkbox_text
---@return string hl_group
local function get_checkbox(is_required, is_visible)
  if is_required then
    return "[*] ", hl.symbols.gray
  elseif is_visible then
    return "[x] ", hl.symbols.header
  else
    return "[ ] ", hl.symbols.header
  end
end

local function get_column_visibility(resource, header)
  local vis = state.column_visibility[resource]
  if not vis or vis[header] == nil then
    return true -- default visible
  end
  return vis[header]
end

--- Reorder headers based on saved column order
---@param resource string
---@param headers string[]
---@return string[]
local function get_ordered_headers(resource, headers)
  local saved_order = state.column_order[resource]
  if not saved_order or #saved_order == 0 then
    return headers
  end

  -- Build a set of current headers for quick lookup
  local header_set = {}
  for _, h in ipairs(headers) do
    header_set[h] = true
  end

  -- Start with headers from saved order that still exist
  local ordered = {}
  local used = {}
  for _, h in ipairs(saved_order) do
    if header_set[h] then
      table.insert(ordered, h)
      used[h] = true
    end
  end

  -- Append any new headers not in saved order
  for _, h in ipairs(headers) do
    if not used[h] then
      table.insert(ordered, h)
    end
  end

  return ordered
end

function M.View(resource_name, headers)
  if not resource_name or not headers or #headers == 0 then
    vim.notify("No columns available for this view", vim.log.levels.WARN)
    return
  end

  M.target_resource = resource_name
  M.target_headers = get_ordered_headers(resource_name, headers)

  -- Update definition title
  M.definition.title = "Columns (" .. resource_name .. ")"

  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition

  vim.schedule(function()
    builder.view_framed(M.definition)

    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(builder.buf_nr, "n", "K", "<Plug>(kubectl.move_up)", opts)
    vim.api.nvim_buf_set_keymap(builder.buf_nr, "n", "J", "<Plug>(kubectl.move_down)", opts)
    vim.api.nvim_buf_set_keymap(builder.buf_nr, "n", "R", "<Plug>(kubectl.reset_order)", opts)
    builder.renderHints()

    -- Add header note
    builder.header = { data = {}, marks = {} }
    table.insert(builder.header.data, "Toggle columns for " .. M.target_resource .. ":")
    table.insert(builder.header.marks, {
      row = #builder.header.data - 1,
      start_col = 0,
      end_col = #builder.header.data[#builder.header.data],
      hl_group = hl.symbols.gray,
    })

    -- Add divider
    tables.generateDividerRow(builder.header.data, builder.header.marks)

    -- Content setup
    builder.col_content = { columns = {} }

    -- Add column lines
    local columns = builder.col_content.columns
    local resource = M.target_resource
    for _, header in ipairs(M.target_headers) do
      local is_required = header == "NAME"
      local is_visible = get_column_visibility(resource, header)
      local checkbox_text, hl_group = get_checkbox(is_required, is_visible)

      columns[#columns + 1] = {
        is_column = true,
        is_required = is_required,
        is_visible = is_visible,
        header = header,
        text = is_required and (header .. " (required)") or header,
        extmarks = {
          {
            start_col = 0,
            virt_text = { { checkbox_text, hl_group } },
            virt_text_pos = "inline",
            right_gravity = false,
          },
        },
      }
    end

    -- Initial draw
    M.Draw()
    builder.fitToContent(2)
  end)
end

function M.Draw()
  local builder = manager.get(M.definition.resource)
  if not builder or not builder.col_content then
    return
  end

  local data = {}
  local extmarks = {}
  local columns = builder.col_content.columns

  for i, line in ipairs(columns) do
    local row = i - 1
    local line_extmarks = line.extmarks
    if line_extmarks then
      local checkbox_text = get_checkbox(line.is_required, line.is_visible)
      for _, ext in ipairs(line_extmarks) do
        ext.row = row
        ext.virt_text[1][1] = checkbox_text
        extmarks[#extmarks + 1] = ext
      end
    end
    data[#data + 1] = line.text
  end

  builder.data = data
  builder.extmarks = extmarks
  builder.displayContentRaw()
end

return M
