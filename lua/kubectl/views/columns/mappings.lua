local columns_view = require("kubectl.views.columns")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local M = {}

--- Get column at current cursor position
local function get_current_column()
  local builder = manager.get("columns")
  if not (builder and builder.processedData and builder.header) then
    return nil
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local idx = row - #builder.header.data

  if idx < 1 or idx > #builder.processedData then
    return nil
  end

  return builder.processedData[idx]
end

local function toggle_column()
  local builder = manager.get("columns")
  local col = get_current_column()
  if not col or not builder then
    return
  end

  if col.is_required then
    vim.notify(col.header .. " column cannot be hidden", vim.log.levels.INFO)
    return
  end

  col.is_visible = not col.is_visible

  local target = columns_view.target_resource
  state.column_visibility[target] = state.column_visibility[target] or {}
  state.column_visibility[target][col.header] = col.is_visible

  columns_view.save_state()
  columns_view.refresh_highlights()
end

local function reset_order()
  local target = columns_view.target_resource
  if not target then
    return
  end

  state.column_order[target] = nil

  local builder = manager.get("columns")
  if builder and builder.frame then
    builder.frame.close()
  end

  local views = require("kubectl.views")
  local _, def = views.resource_and_definition(target)
  if def and def.headers then
    vim.schedule(function()
      columns_view.View(target, def.headers)
    end)
  end
end

local map_opts = { noremap = true, silent = true }

M.overrides = {
  ["<Plug>(kubectl.tab)"] = vim.tbl_extend("force", map_opts, { desc = "toggle", callback = toggle_column }),
  ["<Plug>(kubectl.select)"] = vim.tbl_extend("force", map_opts, { desc = "toggle", callback = toggle_column }),
  ["<Plug>(kubectl.reset_order)"] = vim.tbl_extend("force", map_opts, { desc = "reset order", callback = reset_order }),
}

function M.register()
  local mappings = require("kubectl.mappings")
  mappings.map_if_plug_not_set("n", "R", "<Plug>(kubectl.reset_order)")
end

return M
