local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local string_utils = require("kubectl.utils.string")

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

function M.set_sortby_header()
  local sortby = state.sortby
  if #sortby.mark == 0 then
    local extmark = vim.api.nvim_buf_get_extmark_by_id(0, state.marks.ns_id, state.marks.header[1], { details = true })
    if extmark and #extmark >= 3 then
      local start_row, start_col, end_row, end_col = extmark[1], extmark[2], extmark[3].end_row, extmark[3].end_col
      local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
      local word = string_utils.trim(table.concat(lines, "\n"))

      M.set_virtual_text_on_mark(0, state.marks.ns_id, { state.marks.header[1], start_row, start_col }, word .. " ▼")
    end
  end

  if #sortby.mark > 0 then
    M.set_virtual_text_on_mark(
      0,
      state.marks.ns_id,
      { sortby.mark[1], sortby.mark[2], sortby.mark[3] },
      sortby.current_word .. " ▼"
    )
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
