local M = {}
function M.trim(s)
	return s:match("^%s*(.-)%s*$")
end

return M
