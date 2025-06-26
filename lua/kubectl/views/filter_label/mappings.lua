local fl_view = require("kubectl.views.filter_label")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local utils = require("kubectl.views.filter_label.utils")

local M = {}

local resource = "kubectl_filter_label"

M.overrides = {
  ["<Plug>(kubectl.tab)"] = {
    noremap = true,
    silent = true,
    desc = "toggle label",
    callback = function()
      local store = manager.get(resource)
      if not (store and store.data) then
        return
      end

      local row = vim.api.nvim_win_get_cursor(0)[1]
      local row_iter = vim.iter(store.fl_content)
      local res = row_iter:find(function(row_data)
        return row_data.row == row
      end)

      if not res then
        return
      end
      res.is_selected = not res.is_selected
      fl_view.Draw()
    end,
  },
  ["<Plug>(kubectl.add_label)"] = {
    noremap = true,
    silent = true,
    desc = "new label",
    callback = function()
      local store = manager.get(resource)
      if not (store and store.data) then
        return
      end

      table.insert(state.session_filter_label, "key=value")
      utils.add_existing_labels(store)

      -- -- add label k=v
      -- local new_label = "key=value"
      -- table.insert(store.data, store.labels_len + 1, new_label)
      -- store.labels_len = store.labels_len + 1
      --
      -- -- add checkbox
      -- table.insert(store.extmarks, {
      --   row = store.labels_len - 1,
      --   start_col = 0,
      --   virt_text = { { boxes[1], hl.symbols.header } },
      --   virt_text_pos = "inline",
      --   right_gravity = false,
      -- })
      --
      -- for i, ext in ipairs(store.extmarks) do
      --   if ext.name == "confirmation" then
      --     ext.row = ext.row + 1
      --     store.extmarks[i] = ext
      --     break
      --   end
      -- end

      fl_view.Draw()

      -- move cursor to the new label
      -- vim.api.nvim_win_set_cursor(0, { store.labels_len + #store.header.data, 0 })
    end,
  },
  ["<Plug>(kubectl.delete_label)"] = {
    noremap = true,
    silent = true,
    desc = "delete label",
    callback = function()
      local store = manager.get(resource)
      if not (store and store.data) then
        return
      end

      local row = vim.api.nvim_win_get_cursor(0)[1]
      if row <= #store.header.data or row > store.labels_len + #store.header.data then
        return
      end

      local ext_row = row - #store.header.data - 1 -- 0-based
      local line_idx = nil

      for i, ext in ipairs(store.extmarks) do
        if ext.row == ext_row then
          line_idx = i
        elseif ext.row > ext_row then
          ext.row = ext.row - 1
          store.extmarks[i] = ext
        end
      end

      if line_idx then
        table.remove(store.extmarks, line_idx)
      end

      table.remove(store.data, ext_row + 1)
      store.labels_len = store.labels_len - 1

      fl_view.Draw()
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("n", "o", "<Plug>(kubectl.add_label)")
  mappings.map_if_plug_not_set("n", "dd", "<Plug>(kubectl.delete_label)")
end

return M
