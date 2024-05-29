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

function M.filter_line(array, pattern)
	local filtered_array = {}
	if not pattern then
		return array
	end

	for _, line in ipairs(array) do
		if line:match(pattern) then
			table.insert(filtered_array, line)
		end
	end

	return filtered_array
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
