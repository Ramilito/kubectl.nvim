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

      local label_type, label_idx = utils.get_row_data(store)
      if not (label_type and label_idx) then
        return
      end
      print("label_type: " .. label_type .. ", label_idx: " .. label_idx)
      print("fl: " .. vim.inspect(store.fl_content[label_type]))
      local label_line = store.fl_content[label_type][label_idx]
      if not label_line.is_label then
        return
      end
      label_line.is_selected = not label_line.is_selected

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

      local kv = "key=value"
      table.insert(state.session_filter_label, kv)
      utils.add_existing_labels(store)

      fl_view.Draw()

      -- move cursor to the new label
      vim.api.nvim_win_set_cursor(0, {
        #store.header.data + #store.fl_content.existing_labels - 1,
        1, -- 1-based index
      })
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
        print("not sess_filter_id")
        return
      end

      table.remove(state.session_filter_label, sess_filter_id)
      utils.add_existing_labels(store)
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
