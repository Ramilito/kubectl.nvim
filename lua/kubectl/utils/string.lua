local M = {}

--- Trim whitespace from the beginning and end of a string
---@param s string
---@return string
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

return M
