local M = {}

--- Trim whitespace from the beginning and end of a string
---@param s string
---@return string|nil
function M.trim(s)
  if s then
    return s:match("^%s*(.-)%s*$")
  end
end

return M
