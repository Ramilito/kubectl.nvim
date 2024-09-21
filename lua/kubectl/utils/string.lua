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

function M.get_visual_selection()
  -- does not handle rectangular selection
  local s_start = vim.fn.getpos("'<")
  local s_end = vim.fn.getpos("'>")
  local n_lines = math.abs(s_end[2] - s_start[2]) + 1
  if s_start[2] == 0 then
    s_start[2] = 1
    s_end[2] = 2
    s_end[3] = 1
  end
  local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
  -- return
  lines[1] = string.sub(lines[1], s_start[3], -1)
  if n_lines == 1 then
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3] - s_start[3] + 1)
  else
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3])
  end
  return table.concat(lines, "\n")
end

return M
