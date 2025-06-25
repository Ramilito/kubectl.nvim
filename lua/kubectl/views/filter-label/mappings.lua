local action_view = require("kubectl.views.action")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")

local M = {}

local enum_state = {}

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
    desc = "toggle options",
    callback = function()
      print("that happened!")
      -- local store = manager.get("action_view")
      -- if not (store and store.data) then
      --   return
      -- end
      --
      -- local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
      -- local ns_id = state.marks.ns_id
      --
      -- local ok, ext = pcall(
      --   vim.api.nvim_buf_get_extmarks,
      --   store.buf_nr,
      --   ns_id,
      --   { row, 0 },
      --   { row, 0 },
      --   { details = true, type = "virt_text" }
      -- )
      -- if not (ok and ext[1]) then
      --   return
      -- end
      --
      -- local vt = ext[1][4].virt_text
      -- local key = vt and vt[1] and vt[1][1] -- literal text token
      -- if not key then
      --   return
      -- end
      --
      -- for _, item in ipairs(store.origin_data) do
      --   local opts = item.options
      --   if item.type == "flag" then
      --     opts = { "false", "true" }
      --   end
      --
      --   if opts and key:find(item.text, 1, true) then
      --     local idx = next_idx(opts, enum_state[item.text])
      --     enum_state[item.text] = idx
      --     local offset = 0
      --     if store.header.data then
      --       offset = #store.header.data
      --     end
      --     store.data[row + 1 - offset] = opts[idx]
      --     break
      --   end
      -- end
      --
      -- action_view.Draw()
    end,
  },
}

function M.register()
  print("register")
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
end

return M
