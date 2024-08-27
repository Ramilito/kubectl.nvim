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

--- surround a string with angle brackets for hints
---@param k string
---@return string
function M.s(k)
  -- if the string already has angle brackets, return it as is
  if k:sub(1, 1) == "<" and k:sub(-1) == ">" then
    return k
  end
  return "<" .. k .. ">"
end

return M
