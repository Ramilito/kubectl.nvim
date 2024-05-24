local M = {}
local hl = require("kubectl.view.highlight")
local time = require("kubectl.utils.time")

function M.processRow(rows, headers)
	local data = {}
	for _, row in pairs(rows.items) do
		local pod = {
			namespace = row.metadata.namespace,
			name = row.metadata.name,
			ready = M.getReady(row),
			uptodate = row.status.updatedReplicas,
			available = row.status.availableReplicas,
			age = time.since(row.metadata.creationTimestamp),
		}

		table.insert(data, pod)
	end
	return data
end

function M.getHeaders()
	local headers = {
		"NAMESPACE",
		"NAME",
		"READY",
		"UP-TO-DATE",
		"AVAILABLE",
		"AGE",
	}

	return headers
end

function M.getReady(row)
	return row.status.readyReplicas .. "/" .. row.status.availableReplicas
end

return M
