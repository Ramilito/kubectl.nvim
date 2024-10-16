local M = {}

---@param str string
function M.capitalize(str)
    if str and #str > 0 then
        return str:sub(1, 1):upper() .. str:sub(2)
    else
        return str
    end
end

---@param buf number The buffer number.
---@param char string|nil The divider.
function M.divider(buf, char)
  if not char then
    char = "-"
  end
  local width_of_window = vim.api.nvim_win_get_width(0)
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { string.rep(char, width_of_window) })
  vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
end

--- Gets the text from the current visual selection
---@return string
function M.get_visual_selection()
  local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "x", false)
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  return table.concat(vim.fn.getregion(vstart, vend), "\n")
end

return M
