local columns_view = require("kubectl.views.columns")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")

local M = {}

local resource = "columns"

local function toggle_column()
  local store = manager.get(resource)
  if not (store and store.col_content) then
    return
  end

  local idx = columns_view.get_current_column_index()
  if not idx then
    return
  end

  local col_line = store.col_content.columns[idx]
  if not col_line or not col_line.is_column then
    return
  end

  -- Don't toggle required columns (NAME)
  if col_line.is_required then
    vim.notify("NAME column cannot be hidden", vim.log.levels.INFO)
    return
  end

  -- Toggle visibility
  col_line.is_visible = not col_line.is_visible

  -- Update state
  if not state.column_visibility[columns_view.target_resource] then
    state.column_visibility[columns_view.target_resource] = {}
  end
  state.column_visibility[columns_view.target_resource][col_line.header] = col_line.is_visible

  vim.schedule(function()
    columns_view.Draw()
  end)
end

local function update_column_order(store)
  local order = {}
  for _, col in ipairs(store.col_content.columns) do
    table.insert(order, col.header)
  end
  state.column_order[columns_view.target_resource] = order
end

local function move_column(direction)
  local store = manager.get(resource)
  if not (store and store.col_content) then
    return
  end

  local idx = columns_view.get_current_column_index()
  if not idx then
    return
  end

  local columns = store.col_content.columns
  local target_idx = idx + direction

  -- Bounds check
  if target_idx < 1 or target_idx > #columns then
    return
  end

  -- Swap columns
  columns[idx], columns[target_idx] = columns[target_idx], columns[idx]

  -- Update state for persistence
  update_column_order(store)

  -- Redraw and move cursor to follow the moved column
  vim.schedule(function()
    columns_view.Draw()
    local content_start = #store.header.data
    vim.api.nvim_win_set_cursor(0, { content_start + target_idx, 0 })
  end)
end

local function move_column_up()
  move_column(-1)
end

local function move_column_down()
  move_column(1)
end

M.overrides = {
  ["<Plug>(kubectl.tab)"] = {
    noremap = true,
    silent = true,
    desc = "toggle column",
    callback = toggle_column,
  },
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "toggle column",
    callback = toggle_column,
  },
  ["<Plug>(kubectl.move_up)"] = {
    noremap = true,
    silent = true,
    desc = "move column up",
    callback = move_column_up,
  },
  ["<Plug>(kubectl.move_down)"] = {
    noremap = true,
    silent = true,
    desc = "move column down",
    callback = move_column_down,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
  mappings.map_if_plug_not_set("n", "K", "<Plug>(kubectl.move_up)")
  mappings.map_if_plug_not_set("n", "J", "<Plug>(kubectl.move_down)")
end

return M
