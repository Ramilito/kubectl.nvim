local buffers = require("kubectl.actions.buffers")
local layout = require("kubectl.actions.layout")
local state = require("kubectl.state")
local store = require("kubectl.store")
local M = {}

function M.View(self, definition, data, callback)
  local args = definition.cmd
  local win_config
  self.buf_nr, win_config = buffers.confirmation_buffer(definition.display, definition.ft, function(confirm)
    if confirm then
      callback(args)
    end
  end)

  vim.api.nvim_buf_attach(self.buf_nr, false, {
    on_lines = function(_, buf_nr, _, first, last_orig, last_new, byte_count)
      vim.defer_fn(function()
        if first == last_orig and last_orig == last_new and byte_count == 0 then
          return
        end
        local marks = vim.api.nvim_buf_get_extmarks(
          0,
          state.marks.ns_id,
          0,
          -1,
          { details = true, overlap = true, type = "virt_text" }
        )
        local args_tmp = {}
        for _, value in ipairs(definition.cmd) do
          table.insert(args_tmp, value)
        end

        for _, mark in ipairs(marks) do
          if mark then
            local text = mark[4].virt_text[1][1]
            if string.find(text, "Args", 1, true) then
              vim.api.nvim_buf_set_extmark(buf_nr, state.marks.ns_id, mark[2], 0, {
                id = mark[1],
                virt_text = { { "Params | " .. table.concat(args_tmp, " "), "KubectlWhite" } },
                virt_text_pos = "inline",
                right_gravity = false,
              })
            else
              for _, item in ipairs(data) do
                if string.find(text, item.text, 1, true) then
                  local line_number = mark[2]
                  local line = vim.api.nvim_buf_get_lines(0, line_number, line_number + 1, false)[1] or ""
                  local value = vim.trim(line)

                  if item.type == "flag" then
                    if value == "true" then
                      table.insert(args_tmp, item.cmd)
                    end
                  elseif item.type == "option" then
                    if value ~= "" and value ~= "false" and value ~= nil then
                      table.insert(args_tmp, item.cmd .. "=" .. value)
                    end
                  elseif item.type == "positional" then
                    if value ~= "" and value ~= nil then
                      if item.cmd and item.cmd ~= "" then
                        table.insert(args_tmp, item.cmd .. " " .. value)
                      else
                        table.insert(args_tmp, value)
                      end
                    end
                  elseif item.type == "merge_above" then
                    if value ~= "" and value ~= nil then
                      args_tmp[#args_tmp] = args_tmp[#args_tmp] .. item.cmd .. value
                    end
                  end
                  break
                end
              end
            end
          end
        end
        args = args_tmp
      end, 200)
      vim.defer_fn(function()
        if vim.api.nvim_get_current_buf() == buf_nr then
          local win_nr = vim.api.nvim_get_current_win()
          layout.win_size_fit_content(buf_nr, win_nr, 2, #table.concat(args) + 40)
        end
      end, 1000)
    end,
  })

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

  table.insert(self.extmarks, {
    row = #self.data - 1,
    start_col = 0,
    virt_text = { { "Params | " .. " ", "KubectlWhite" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })

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
