local M = {}
local hl = require("kubectl.view.highlight")
local time = require("kubectl.utils.time")

function M.processRow(rows)
	local data = {}
	for _, row in pairs(rows.items) do
		local pod = {
			namespace = row.metadata.namespace,
			lastseen = row.lastTimestamp,
			type = row.type,
			reason = row.reason,
			object = row.involvedObject.name,
			message = row.message,
			count = row.count,
		}

		table.insert(data, pod)
	end
	return data
end

function M.getHeaders()
	local headers = {
		"NAMESPACE",
		"LASTSEEN",
		"TYPE",
		"REASON",
		"OBJECT",
		"MESSAGE",
		"COUNT",
	}

	return headers
end

return M
