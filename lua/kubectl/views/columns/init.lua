local definition = require("kubectl.views.columns.definition")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = definition.definition,
  target_resource = nil,
  col_master = {},
  syncing = false,
}

local ns_name = "__kubectl_views"

--- Get checkbox prefix based on column state
local function get_checkbox(col)
  if col.is_required then
    return "[*]"
  elseif col.is_visible then
    return "[x]"
  else
    return "[ ]"
  end
end

--- Build display line for a column (header only, checkbox via extmark)
local function build_line(col)
  return col.header
end

--- Save current column state to session
function M.save_state()
  local session_name = state.context["current-context"]
  if session_name and state.session.contexts[session_name] then
    state.set_session(state.session.contexts[session_name].view)
  end
end

--- Reorder headers based on saved column order
local function get_ordered_headers(resource, headers)
  local saved_order = state.column_order[resource]
  if not saved_order or #saved_order == 0 then
    return headers
  end

  local header_set = {}
  for _, h in ipairs(headers) do
    header_set[h] = true
  end

  local ordered, used = {}, {}
  for _, h in ipairs(saved_order) do
    if header_set[h] then
      ordered[#ordered + 1] = h
      used[h] = true
    end
  end

  for _, h in ipairs(headers) do
    if not used[h] then
      ordered[#ordered + 1] = h
    end
  end

  return ordered
end

--- Create column objects from headers
local function build_columns(headers, resource)
  local columns = {}
  M.col_master = {}

  for _, header in ipairs(headers) do
    local is_required = tables.required_headers[header] or false
    local is_visible = (state.column_visibility[resource] or {})[header] ~= false
    local col = {
      header = header,
      is_required = is_required,
      is_visible = is_visible,
    }
    columns[#columns + 1] = col
    M.col_master[header] = col
  end

  return columns
end

--- Apply checkbox extmarks (virtual text, not editable)
function M.refresh_highlights()
  local builder = manager.get(M.definition.resource)
  if not builder or not builder.processedData or not vim.api.nvim_buf_is_valid(builder.buf_nr) then
    return
  end

  local header_count = builder.header and #builder.header.data or 0
  local ns = vim.api.nvim_create_namespace(ns_name)

  vim.api.nvim_buf_clear_namespace(builder.buf_nr, ns, 0, -1)

  for i, col in ipairs(builder.processedData) do
    local row = header_count + i - 1
    local checkbox = get_checkbox(col) .. " "
    local hl_group
    if col.is_required then
      hl_group = hl.symbols.gray
    elseif col.is_visible then
      hl_group = hl.symbols.success
    else
      hl_group = hl.symbols.gray
    end

    -- Display checkbox as inline virtual text (not editable)
    vim.api.nvim_buf_set_extmark(builder.buf_nr, ns, row, 0, {
      virt_text = { { checkbox, hl_group } },
      virt_text_pos = "inline",
    })
  end
end

--- Sync buffer lines to state (called on TextChanged)
function M.sync_from_buffer()
  if M.syncing then
    return
  end

  local builder = manager.get(M.definition.resource)
  if not builder or not builder.processedData or not M.target_resource then
    return
  end

  local header_count = builder.header and #builder.header.data or 0
  local lines = vim.api.nvim_buf_get_lines(builder.buf_nr, header_count, -1, false)

  local new_columns, new_order = {}, {}
  for _, line in ipairs(lines) do
    local header = vim.trim(line)
    if header ~= "" and M.col_master[header] then
      new_columns[#new_columns + 1] = M.col_master[header]
      new_order[#new_order + 1] = header
    end
  end

  if #new_columns > 0 then
    builder.processedData = new_columns
    state.column_order[M.target_resource] = new_order
    M.save_state()
    M.refresh_highlights()
  end
end

function M.View(resource_name, headers)
  if not resource_name or not headers or #headers == 0 then
    vim.notify("No columns available for this view", vim.log.levels.WARN)
    return
  end

  M.target_resource = resource_name
  M.definition.title = "Columns (" .. resource_name .. ")"

  local ordered_headers = get_ordered_headers(resource_name, headers)
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.view_framed(M.definition)

  -- Disable any formatting that could interfere with paste
  vim.api.nvim_set_option_value("formatoptions", "", { buf = builder.buf_nr })
  vim.api.nvim_set_option_value("textwidth", 0, { buf = builder.buf_nr })

  -- Build column data with checkbox prefix
  builder.processedData = build_columns(ordered_headers, resource_name)
  builder.data = vim.tbl_map(function(col)
    return build_line(col)
  end, builder.processedData)

  -- Header
  builder.header = { data = {}, marks = {} }
  builder.header.data[1] = "Toggle columns for " .. resource_name .. ":"
  builder.header.marks[1] = {
    row = 0,
    start_col = 0,
    end_col = #builder.header.data[1],
    hl_group = hl.symbols.gray,
  }
  tables.generateDividerRow(builder.header.data, builder.header.marks)

  -- Render content
  M.syncing = true
  builder.displayContentRaw()
  builder.fitToContent(2)

  vim.schedule(function()
    M.refresh_highlights()
    M.syncing = false
  end)

  -- Setup buffer sync
  vim.api.nvim_buf_set_keymap(builder.buf_nr, "n", "R", "<Plug>(kubectl.reset_order)", {
    noremap = true,
    silent = true,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = builder.buf_nr,
    callback = function()
      vim.schedule(M.sync_from_buffer)
    end,
  })
end

return M
