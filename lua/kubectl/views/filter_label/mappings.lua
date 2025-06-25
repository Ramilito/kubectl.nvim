local find = require("kubectl.utils.find")
local fl_view = require("kubectl.views.filter_label")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")

local M = {}

local boxes = { "[ ] ", "[x] " }
local resource = "kubectl_filter_label"

---@param list string[]   the option list
---@param idx  integer?   last index (or nil the first time)
---@return integer        next index in [1..#list]
local function next_idx(list, idx)
  idx = (idx or 0) + 1
  return ((idx - 1) % #list) + 1 -- simple modulo cycle
end

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

      local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
      local ns_id = state.marks.ns_id
      --
      local ok, ext = pcall(
        vim.api.nvim_buf_get_extmarks,
        store.buf_nr,
        ns_id,
        { row, 0 },
        { row, 0 },
        { details = true, type = "virt_text" }
      )
      if not (ok and ext[1]) then
        return
      end
      --
      local vt = ext[1][4].virt_text
      local checkbox = vt and vt[1] and vt[1][1] -- literal text token
      if not checkbox or not vim.tbl_contains(boxes, checkbox) then
        return
      end
      local box_idx = find.tbl_idx(boxes, checkbox)
      local next_box = boxes[next_idx(boxes, box_idx)]

      -- update the checkbox extmark
      vim.api.nvim_buf_set_extmark(store.buf_nr, ns_id, row, 0, {
        id = ext[1][1],
        virt_text = { { next_box, hl.symbols.header } },
        virt_text_pos = "inline",
      })
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

      -- add label k=v
      local new_label = "key=value"
      table.insert(store.data, store.labels_len + 1, new_label)
      store.labels_len = store.labels_len + 1

      -- add checkbox
      table.insert(store.extmarks, {
        row = store.labels_len - 1,
        start_col = 0,
        virt_text = { { boxes[1], hl.symbols.header } },
        virt_text_pos = "inline",
        right_gravity = false,
      })

      for i, ext in ipairs(store.extmarks) do
        if ext.name == "confirmation" then
          ext.row = ext.row + 1
          store.extmarks[i] = ext
          break
        end
      end

      fl_view.Draw()
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
