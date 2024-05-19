local M = {}
local api = vim.api

local function getNestedValue(tbl, path)
	local function parseKey(key)
		local isArrayIndex = string.match(key, "^%[(%d+)%]$")
		if isArrayIndex then
			return tonumber(isArrayIndex)
		else
			return key
		end
	end

	local parts = {}
	for part in string.gmatch(path, "[^%.%[%]]+") do
		table.insert(parts, part)
	end

	local value = tbl
	for _, key in ipairs(parts) do
		key = parseKey(key)
		if value[key] then
			value = value[key]
		else
			return nil -- Return nil if any key in the path doesn't exist
		end
	end
	return value
end

-- Function to calculate column widths
local function calculate_column_widths(rows, columns)
	local widths = {}
	for _, row in ipairs(rows) do
		for _, column in pairs(columns) do
			widths[column] = math.max(widths[column] or 0, #tostring(row[column]))
		end
	end

	return widths
end

-- Function to print the table
function M.table(rows)
	local tbl = ""
	local pods = {}

	for _, row in pairs(rows.items) do
		local restartCount = 0
		for _, value in ipairs(row.status.containerStatuses) do
			restartCount = restartCount + value.restartCount
		end
		local pod = {
			namespace = row.metadata.namespace,
			name = row.metadata.name,
			phase = row.status.phase,
			restarts = restartCount,
			ready = "1/1",
		}
		table.insert(pods, pod)
	end

	local columns = {
		"namespace",
		"name",
		"ready",
		"phase",
		"restarts",
	}

	local widths = calculate_column_widths(pods, columns)
	for key, value in pairs(widths) do
		widths[key] = math.max(#key, value)
	end

	print(vim.inspect(widths))
	tbl = "NAMESPACE"
		.. string.rep(" ", widths[columns[1]] - #"NAMESPACE" + 1)
		.. "NAME"
		.. string.rep(" ", widths[columns[2]] - #"NAME" + 1)
		.. "READY"
		.. string.rep(" ", widths[columns[3]] - #"READY" + 1)
		.. "STATUS"
		.. string.rep(" ", widths[columns[4]] - #"STATUS" + 1)
		.. "RESTARTS"
		.. string.rep(" ", widths[columns[5]] - #"RESTARTS" + 1)
		.. "\n"

	for _, row in pairs(pods) do
		local pod = row.namespace
			.. string.rep(" ", widths[columns[1]] - #row.namespace + 1)
			.. row.name
			.. string.rep(" ", widths[columns[2]] - #row.name + 1)
			.. row.ready
			.. string.rep(" ", widths[columns[3]] - #row.ready + 1)
			.. row.phase
			.. string.rep(" ", widths[columns[4]] - #row.phase + 1)
			.. row.restarts
			.. string.rep(" ", widths[columns[5]] - #tostring(row.restarts) + 1)
			.. "\n"

		tbl = tbl .. pod
	end
	return vim.split(tbl, "\n")
end

return M
