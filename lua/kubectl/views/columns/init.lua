local definition = require("kubectl.views.columns.definition")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local views = require("kubectl.views")

local M = {
  definition = definition.definition,
  target_resource = nil,
  target_headers = nil,
}

local function get_column_visibility(resource, header)
  local vis = state.column_visibility[resource]
  if not vis then
    return true -- default visible
  end
  if vis[header] == nil then
    return true -- default visible
  end
  return vis[header]
end

local function save_visibility()
  local session_name = state.context["current-context"]
  if session_name and state.session.contexts[session_name] then
    state.set_session(state.session.contexts[session_name].view)
  end
end

local function on_close(_builder)
  save_visibility()
  -- Refresh the parent view
  local view, _ = views.resource_and_definition(M.target_resource)
  if view and view.Draw then
    vim.schedule(function()
      view.Draw()
    end)
  end
end

local function display_float(builder)
  builder.view_framed(M.definition)

  local win = builder.win_nr

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
  for _, header in ipairs(M.target_headers) do
    local is_required = header == "NAME"
    local is_visible = get_column_visibility(M.target_resource, header)

    local checkbox_text
    if is_required then
      checkbox_text = "[*] "
    elseif is_visible then
      checkbox_text = "[x] "
    else
      checkbox_text = "[ ] "
    end

    local hl_group = is_required and hl.symbols.gray or hl.symbols.header

    table.insert(builder.col_content.columns, {
      is_column = true,
      is_required = is_required,
      is_visible = is_visible,
      header = header,
      text = header .. (is_required and " (required)" or ""),
      extmarks = {
        {
          start_col = 0,
          virt_text = { { checkbox_text, hl_group } },
          virt_text_pos = "inline",
          right_gravity = false,
        },
      },
    })
  end

  -- Setup close autocmd
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      on_close(builder)
    end,
  })

  -- Initial draw
  M.Draw()
  builder.fitToContent(2)
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
    display_float(builder)
  end)
end

function M.Draw()
  local builder = manager.get(M.definition.resource)
  if not builder then
    return
  end

  builder.data = {}
  builder.extmarks = {}

  for i, line in ipairs(builder.col_content.columns) do
    -- Update extmark row
    for _, ext in ipairs(line.extmarks or {}) do
      ext.row = i - 1

      -- Update checkbox text
      local checkbox_text
      if line.is_required then
        checkbox_text = "[*] "
      elseif line.is_visible then
        checkbox_text = "[x] "
      else
        checkbox_text = "[ ] "
      end
      ext.virt_text[1][1] = checkbox_text
    end

    table.insert(builder.data, line.text)
    vim.list_extend(builder.extmarks, line.extmarks or {})
  end

  builder.displayContentRaw()
end

--- Get current row's column info
---@return number|nil index
function M.get_current_column_index()
  local builder = manager.get(M.definition.resource)
  if not builder or not builder.col_content then
    return nil
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local content_start = #builder.header.data

  local idx = row - content_start
  if idx >= 1 and idx <= #builder.col_content.columns then
    return idx
  end
  return nil
end

return M
