local state = require("kubectl.state")

local M = {}

--- Get the current mark and the current word under the cursor
---@param row number|nil Row number (1-indexed, optional)
---@param bufnr number|nil Buffer number (optional, defaults to current buffer)
---@return table|nil, string
function M.get_current_mark(row, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  row = row or cursor[1]
  row = row - 1
  local col = cursor[2]
  local current_word = ""
  local mark = nil

  local buf_state = state.get_buffer_state(bufnr)
  local line_marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    buf_state.ns_id,
    { row, 0 },
    { row, -1 },
    { details = true, overlap = true, type = "virt_text" }
  )

  for _, value in ipairs(line_marks) do
    local mark_col = value[3]
    local content = value[4]
    if col >= mark_col and col <= mark_col + #content.virt_text[1][1] then
      mark = value
      current_word = vim.trim(content.virt_text[1][1])
    end
  end

  return mark, current_word
end

return M
