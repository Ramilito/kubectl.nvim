local M = {}

--- Trim whitespace from the beginning and end of a string
---@param s string
---@return string
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

function M.capitalize(str)
  return str:sub(1, 1):upper() .. str:sub(2)
end

function M.divider(buf, char)
  if not char then
    char = "-"
  end
  local width_of_window = vim.api.nvim_win_get_width(0)
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { string.rep(char, width_of_window) })
  vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
end

return M
