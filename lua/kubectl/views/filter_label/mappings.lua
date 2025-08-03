local fl_view = require("kubectl.views.filter_label")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local utils = require("kubectl.views.filter_label.utils")

local M = {}

local resource = "filter_label"

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

      local label_type, label_idx = utils.get_row_data(store)
      if not (label_type and label_idx) then
        return
      end
      local label_line = store.fl_content[label_type][label_idx]
      if not label_line.is_label then
        return
      end
      label_line.is_selected = not label_line.is_selected

      vim.schedule(function()
        utils.event = "toggle"
        fl_view.Draw()
      end)
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

      local kv = "key=value"
      table.insert(state.filter_label_history, kv)
      utils.add_existing_labels(store)
      vim.schedule(function()
        utils.event = "add"
        fl_view.Draw()

        -- move cursor to the new label
        vim.api.nvim_win_set_cursor(0, {
          #store.header.data + #state.filter_label_history + 1,
          1,
        })
      end)
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

      local label_type, label_idx = utils.get_row_data(store)
      if not (label_type and label_idx) then
        return
      end
      local sess_filter_id = store.fl_content[label_type][label_idx].sess_filter_id
      if not sess_filter_id then
        return
      end

      table.remove(state.filter_label_history, sess_filter_id)
      utils.add_existing_labels(store)
      vim.schedule(function()
        utils.event = "delete"
        fl_view.Draw()
      end)
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("n", "o", "<Plug>(kubectl.add_label)")
  mappings.map_if_plug_not_set("n", "dd", "<Plug>(kubectl.delete_label)")
end

return M
