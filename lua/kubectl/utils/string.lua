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

function M.path_join(...)
  local v, _ = table.concat(util.tbl_flatten({ ... }), path_separator):gsub(path_separator .. "+", path_separator)
  return v
end

return M
