local M = {}

function M.escape(s)
	local matches = {
		["^"] = "%^",
		["$"] = "%$",
		["("] = "%(",
		[")"] = "%)",
		["%"] = "%%",
		["."] = "%.",
		["["] = "%[",
		["]"] = "%]",
		["*"] = "%*",
		["+"] = "%+",
		["-"] = "%-",
		["?"] = "%?",
	}
	return (s:gsub(".", matches))
end

function M.array(array, match_func)
	for _, item in ipairs(array) do
		if match_func(item) then
			return item
		end
	end
	return nil
end
function M.dictionary(dict, match_func)
	for key, value in pairs(dict) do
		if match_func(key, value) then
			return key, value
		end
	end
	return nil, nil -- Return nil if no match is found
end

return M
