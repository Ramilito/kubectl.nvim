local buffers = require("kubectl.actions.buffers")
local state = require("kubectl.state")
local store = require("kubectl.store")
local M = {}

local get_values = function(definition, data)
  local marks =
    vim.api.nvim_buf_get_extmarks(0, state.marks.ns_id, 0, -1, { details = true, overlap = true, type = "virt_text" })
  local args_tmp = {}
  for _, value in ipairs(definition.cmd) do
    table.insert(args_tmp, value)
  end

  for _, mark in ipairs(marks) do
    if mark then
      local text = mark[4].virt_text[1][1]
      for _, item in ipairs(data) do
        if string.find(text, item.text, 1, true) then
          local line_number = mark[2]
          local line = vim.api.nvim_buf_get_lines(0, line_number, line_number + 1, false)[1] or ""
          local value = vim.trim(line)

          item.value = value
          table.insert(args_tmp, item)
        end
      end
    end
  end
  return args_tmp
end

function M.View(self, definition, data, callback)
  local win_config
  self.buf_nr, win_config = buffers.confirmation_buffer(definition.display, definition.ft, function(confirm)
    local args = get_values(definition, data)
    if confirm then
      callback(args)
    end
  end)

  for _, item in ipairs(data) do
    table.insert(self.data, item.value)
    table.insert(self.extmarks, {
      row = #self.data - 1,
      start_col = 0,
      virt_text = { { item.text .. " ", "KubectlHeader" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  table.insert(self.data, "")
  table.insert(self.data, "")

  local confirmation = "[y]es [n]o"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
  table.insert(self.extmarks, {
    row = #self.data - 1,
    start_col = 0,
    virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
    virt_text_pos = "inline",
  })

  self:setContentRaw()
  vim.cmd([[syntax match KubectlPending /.*/]])
  store.set("action", { self = self, data = data })
end

return M
