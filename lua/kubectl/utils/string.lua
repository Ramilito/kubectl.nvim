local M = {}

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
  local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "x", false)
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  return table.concat(vim.fn.getregion(vstart, vend), "\n")
end

return M
