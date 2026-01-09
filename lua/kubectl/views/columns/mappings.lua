local columns_view = require("kubectl.views.columns")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")

local M = {}

local resource = "columns"

local function save_state()
  local session_name = state.context["current-context"]
  if session_name and state.session.contexts[session_name] then
    state.set_session(state.session.contexts[session_name].view)
  end
end

--- Get current row's column info
---@return number|nil index
local function get_current_column_index()
  local builder = manager.get(resource)
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

--- Returns store, index, and column for current cursor position
--- @return table|nil store
--- @return number|nil idx
--- @return table|nil col
local function get_current_column()
  local store = manager.get(resource)
  if not (store and store.col_content) then
    return nil, nil, nil
  end
  local idx = get_current_column_index()
  if not idx then
    return store, nil, nil
  end
  local col = store.col_content.columns[idx]
  if not col or not col.is_column then
    return store, idx, nil
  end
  return store, idx, col
end

local function toggle_column()
  local _, _, col = get_current_column()
  if not col then
    return
  end
  if col.is_required then
    vim.notify("NAME column cannot be hidden", vim.log.levels.INFO)
    return
  end
  col.is_visible = not col.is_visible
  local target = columns_view.target_resource
  state.column_visibility[target] = state.column_visibility[target] or {}
  state.column_visibility[target][col.header] = col.is_visible
  save_state()
  vim.schedule(columns_view.Draw)
end

local function move_column(direction)
  local store, idx = get_current_column()
  if not (store and idx) then
    return
  end
  local columns = store.col_content.columns
  local target_idx = idx + direction
  if target_idx < 1 or target_idx > #columns then
    return
  end
  columns[idx], columns[target_idx] = columns[target_idx], columns[idx]
  local order = {}
  for _, col in ipairs(columns) do
    order[#order + 1] = col.header
  end
  state.column_order[columns_view.target_resource] = order
  save_state()
  vim.schedule(function()
    columns_view.Draw()
    vim.api.nvim_win_set_cursor(0, { #store.header.data + target_idx, 0 })
  end)
end

local function reset_order()
  local target = columns_view.target_resource
  if not target then
    return
  end
  state.column_order[target] = nil
  local store = manager.get(resource)
  if store and store.frame then
    store.frame.close()
  end
  local views = require("kubectl.views")
  local view, def = views.resource_and_definition(target)
  if view and def and def.headers then
    vim.schedule(function()
      columns_view.View(target, def.headers)
    end)
  end
end

M.overrides = {
  ["<Plug>(kubectl.tab)"] = { noremap = true, silent = true, desc = "toggle column", callback = toggle_column },
  ["<Plug>(kubectl.select)"] = { noremap = true, silent = true, desc = "toggle column", callback = toggle_column },
  ["<Plug>(kubectl.move_up)"] = {
    noremap = true,
    silent = true,
    desc = "move column up",
    callback = function()
      move_column(-1)
    end,
  },
  ["<Plug>(kubectl.move_down)"] = {
    noremap = true,
    silent = true,
    desc = "move column down",
    callback = function()
      move_column(1)
    end,
  },
  ["<Plug>(kubectl.reset_order)"] = {
    noremap = true,
    silent = true,
    desc = "reset column order",
    callback = reset_order,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
  mappings.map_if_plug_not_set("n", "K", "<Plug>(kubectl.move_up)")
  mappings.map_if_plug_not_set("n", "J", "<Plug>(kubectl.move_down)")
  mappings.map_if_plug_not_set("n", "R", "<Plug>(kubectl.reset_order)")
end

return M
