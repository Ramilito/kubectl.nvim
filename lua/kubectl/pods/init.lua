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
			status = M.getPodStatus(row.status.phase),
			restarts = M.getRestarts(row),
			node = row.spec.nodeName,
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
		"STATUS",
		"RESTARTS",
		"NODE",
		"AGE",
	}

	return headers
end

function M.getReady(row)
	local readyCount = 0
	local containers = 0
	for _, value in ipairs(row.status.containerStatuses) do
		containers = containers + 1
		if value.ready then
			readyCount = readyCount + 1
		end
	end
	return readyCount .. "/" .. containers
end

function M.getRestarts(row)
	local restartCount = 0
	local lastState
	for _, value in ipairs(row.status.containerStatuses) do
		if value.lastState and value.lastState.terminated then
			lastState = time.since(value.lastState.terminated.finishedAt)
		end
		restartCount = restartCount + value.restartCount
	end
	if lastState then
		return restartCount .. " (" .. lastState .. " ago)"
	else
		return restartCount
	end
end

function M.getPodStatus(phase)
	local status = { symbol = "", value = phase }
	if phase == "Running" then
		status.symbol = hl.symbols.success
	elseif phase == "Pending" or phase == "Terminating" or phase == "ContainerCreating" then
		status.symbol = hl.symbols.pending
	elseif
		phase == "Failed"
		or phase == "RunContainerError"
		or phase == "ErrImagePull"
		or phase == "ImagePullBackOff"
		or phase == "Error"
		or phase == "OOMKilled"
	then
		status.symbol = hl.symbols.error
	end

	return status
end

return M
