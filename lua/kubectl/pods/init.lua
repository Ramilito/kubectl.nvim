local M = {}
local hl = require("kubectl.view.highlight")

function M.processRow(rows, headers)
	local data = {}
	for _, row in pairs(rows.items) do
		local restartCount = 0
		local containers = 0
		local readyCount = 0
		for _, value in ipairs(row.status.containerStatuses) do
			containers = containers + 1
			if value.ready then
				readyCount = readyCount + 1
			end
			restartCount = restartCount + value.restartCount
		end

		local pod = {
			namespace = row.metadata.namespace,
			name = row.metadata.name,
			status = M.getPodStatus(row.status.phase),
			restarts = restartCount,
			ready = readyCount .. "/" .. containers,
		}

		table.insert(data, pod)
	end
	return data
end

function M.getPodStatus(phase)
	if phase == "Running" then
		return hl.symbols.success .. phase
	elseif phase == "Pending" or phase == "Terminating" or phase == "ContainerCreating" then
		return hl.symbols.pending .. phase
	elseif
		phase == "Failed"
		or phase == "RunContainerError"
		or phase == "ErrImagePull"
		or phase == "ImagePullBackOff"
		or phase == "Error"
		or phase == "OOMKilled"
	then
		return hl.symbols.error .. phase
	end

	return phase
end

return M
