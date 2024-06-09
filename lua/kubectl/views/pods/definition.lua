local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local M = {}

local function getPorts(ports)
  local string_ports = ""
  if ports then
    for index, value in ipairs(ports) do
      string_ports = string_ports .. value.containerPort .. "/" .. value.protocol

      if index < #ports then
        string_ports = string_ports .. ","
      end
    end
  end
  return string_ports
end

local function getContainerState(state)
  for key, _ in pairs(state) do
    return key
  end
end

function M.processContainerRow(row)
  local data = {}

  for _, container in pairs(row.spec.containers) do
    for _, status in ipairs(row.status.containerStatuses) do
      if status.name == container.name then
        local result = {
          name = container.name,
          image = container.image,
          ready = status.ready,
          state = getContainerState(status.state),
          init = false,
          restarts = status.restartCount,
          ports = getPorts(container.ports),
          age = time.since(row.metadata.creationTimestamp),
        }

        table.insert(data, result)
      end
    end
  end
  return data
end

function M.getContainerHeaders()
  local headers = {
    "NAME",
    "IMAGE",
    "READY",
    "STATE",
    "INIT",
    "RESTARTS",
    "PORTS",
    "AGE",
  }

  return headers
end

function M.processRow(rows)
  local data = {}
  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = M.getReady(row),
        status = M.getPodStatus(row.status.phase),
        restarts = M.getRestarts(row),
        node = row.spec.nodeName,
        age = time.since(row.metadata.creationTimestamp, true),
      }

      table.insert(data, pod)
    end
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
  local status = { symbol = "", value = "" }
  local readyCount = 0
  local containers = 0
  if row.status.containerStatuses then
    for _, value in ipairs(row.status.containerStatuses) do
      containers = containers + 1
      if value.ready then
        readyCount = readyCount + 1
      end
    end
  end
  if readyCount == containers then
    status.symbol = hl.symbols.note
  else
    status.symbol = hl.symbols.deprecated
  end
  status.value = readyCount .. "/" .. containers
  return status
end

function M.getRestarts(row)
  local restartCount = 0
  local lastState

  if not row.status.containerStatuses then
    return restartCount
  end

  for _, value in ipairs(row.status.containerStatuses) do
    if value.lastState and value.lastState.terminated then
      lastState = time.since(value.lastState.terminated.finishedAt)
    end
    restartCount = restartCount + value.restartCount
  end
  if lastState then
    return restartCount .. " (" .. lastState.value .. " ago)"
  else
    return restartCount
  end
end

function M.getPodStatus(phase)
  local status = { symbol = "", value = phase }
  if phase == "Running" then
    status.symbol = hl.symbols.success
  elseif phase == "Pending" or phase == "Terminating" or phase == "ContainerCreating" then
    status.symbol = hl.symbols.debug
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
