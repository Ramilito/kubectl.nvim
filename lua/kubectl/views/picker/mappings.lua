local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local M = {}

local function select_item()
  local builder = manager.get("Picker")
  if not builder or not builder.processedData then
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local data_idx = row - 1 -- Account for header row
  local item = builder.processedData[data_idx]
  if not item or not item._entry then
    return
  end

  local entry = item._entry
  vim.cmd("fclose!")
  vim.schedule(function()
    if not vim.api.nvim_tabpage_is_valid(entry.tab_id) then
      vim.cmd("tabnew")
      entry.tab_id = vim.api.nvim_get_current_tabpage()
    end
    vim.schedule(function()
      vim.api.nvim_set_current_tabpage(entry.tab_id)
      entry.open(unpack(entry.args))
    end)
  end)
end

local function delete_item()
  local builder = manager.get("Picker")
  if not builder or not builder.processedData then
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local data_idx = row - 1 -- Account for header row
  local item = builder.processedData[data_idx]
  if item and item._entry then
    state.picker_remove(item._entry.key)
    table.remove(builder.processedData, data_idx)
    pcall(vim.api.nvim_buf_set_lines, 0, row - 1, row, false, {})
  end
end

local map_opts = { noremap = true, silent = true }

M.overrides = {
  ["<Plug>(kubectl.select)"] = vim.tbl_extend("force", map_opts, { desc = "select", callback = select_item }),
  ["<Plug>(kubectl.delete)"] = vim.tbl_extend("force", map_opts, { desc = "delete", callback = delete_item }),
}

function M.register()
  local mappings = require("kubectl.mappings")
  mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
end

return M
