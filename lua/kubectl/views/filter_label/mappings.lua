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

      if label_type == "res_labels" and label_line.is_selected then
        table.insert(state.filter_label_history, label_line.text)
        table.insert(state.filter_label, label_line.text)
        utils.add_existing_labels(store)
        utils.add_res_labels(store, fl_view.resource_definition.gvk.k)
      end

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
      if state.filter_label_history then
        table.insert(state.filter_label_history, kv)
      end
      utils.add_existing_labels(store)
      utils.add_res_labels(store, fl_view.resource_definition.gvk.k)
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

      local deleted_label = state.filter_label_history[sess_filter_id]
      table.remove(state.filter_label_history, sess_filter_id)

      for i, label in ipairs(state.filter_label) do
        if label == deleted_label then
          table.remove(state.filter_label, i)
          break
        end
      end

      utils.add_existing_labels(store)
      utils.add_res_labels(store, fl_view.resource_definition.gvk.k)
      vim.schedule(function()
        utils.event = "delete"
        fl_view.Draw()
      end)
    end,
  },
  ["<Plug>(kubectl.refresh)"] = {
    noremap = true,
    silent = true,
    desc = "refresh view",
    callback = function()
      local store = manager.get(resource)
      if not store then
        return
      end

      utils.add_existing_labels(store)
      utils.add_res_labels(store, fl_view.resource_definition.gvk.k)
      vim.schedule(function()
        fl_view.Draw()
      end)
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("n", "o", "<Plug>(kubectl.add_label)")
  mappings.map_if_plug_not_set("n", "dd", "<Plug>(kubectl.delete_label)")
  mappings.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
end

return M
