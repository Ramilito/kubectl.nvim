local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local M = {}
function M.get_current_mark()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- Convert to 0-based indexing
  local col = cursor[2]

  local marks = vim.api.nvim_buf_get_extmarks(0, state.marks.ns_id, { row, col }, { row, col }, { details = true })

  local current_word = vim.fn.expand("<cword>")
  if #marks > 0 then
    return marks[1], current_word
  else
    return nil
  end
end

function M.set_virtual_text_on_mark(bufnr, ns_id, mark, virt_text)
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, mark[2], mark[3], {
    id = mark[1],
    virt_text = { { virt_text, hl.symbols.header } },
    virt_text_pos = "overlay",
  })
end

return M
