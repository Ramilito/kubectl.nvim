local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local store = require("kubectl.store")

local M = {}

local current_enums = {}
M.overrides = {
  ["<Plug>(kubectl.tab)"] = {
    noremap = true,
    silent = true,
    desc = "toggle options",
    callback = function()
      local action_store = store.get("action")
      local data = action_store.data
      local self = action_store.self
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      local marks_ok, marks = pcall(
        vim.api.nvim_buf_get_extmarks,
        0,
        state.marks.ns_id,
        { current_line - 1, 0 },
        { current_line - 1, 0 },
        { details = true, overlap = true, type = "virt_text" }
      )
      if not marks_ok or not marks[1] then
        return
      end
      local mark = marks[1][4]
      local key
      if mark then
        key = mark.virt_text[1][1]
      end
      for _, item in ipairs(data) do
        if item.type == "flag" then
          item.options = { "false", "true" }
        end
        if string.match(key, item.text) and item.options then
          if current_enums[item.text] == nil then
            current_enums[item.text] = 2
          else
            current_enums[item.text] = current_enums[item.text] + 1
            if current_enums[item.text] > #item.options then
              current_enums[item.text] = 1
            end
          end
          self.data[current_line] = item.options[current_enums[item.text]]
          self:setContentRaw()
        end
      end
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
end

return M
