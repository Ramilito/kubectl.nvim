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
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
end

return M
