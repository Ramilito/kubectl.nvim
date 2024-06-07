local M = {}
function M.trim(s)
  if s then
    return s:match("^%s*(.-)%s*$")
  end
end

return M
