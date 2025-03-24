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
  local key = next(state)
  return key
end

local function addContainers(row, data)
  if row.spec and row.status and row.status.containerStatuses then
    for _, container in pairs(row.spec.containers) do
      for _, status in ipairs(row.status.containerStatuses) do
        if status.name == container.name then
          local result = {
            name = container.name,
            image = container.image,
            ready = status.ready,
            state = getContainerState(status.state),
            type = "container",
            restarts = status.restartCount,
            ports = getPorts(container.ports),
            age = time.since(row.metadata.creationTimestamp),
          }

          table.insert(data, result)
        end
      end
    end
  end
end

local function addInitContianers(row, data)
  if row.spec and row.status and row.status.initContainerStatuses then
    for _, container in pairs(row.spec.initContainers) do
      for _, status in ipairs(row.status.initContainerStatuses) do
        if status.name == container.name then
          local result = {
            name = container.name,
            image = container.image,
            ready = status.ready,
            state = getContainerState(status.state),
            type = "init",
            restarts = status.restartCount,
            ports = getPorts(container.ports),
            age = time.since(row.metadata.creationTimestamp),
          }

          table.insert(data, result)
        end
      end
    end
  end
end
local function addEphemeralContianers(row, data)
  if row.spec and row.status and row.status.ephemeralContainerStatuses then
    for _, container in pairs(row.spec.ephemeralContainers) do
      for _, status in ipairs(row.status.ephemeralContainerStatuses) do
        if status.name == container.name then
          local result = {
            name = container.name,
            image = container.image,
            ready = status.ready,
            state = getContainerState(status.state),
            type = "ephemeral",
            restarts = status.restartCount,
            ports = getPorts(container.ports),
            age = time.since(row.metadata.creationTimestamp),
          }

          table.insert(data, result)
        end
      end
    end
  end
end

function M.processRow(row)
  local data = {}
  addContainers(row, data)
  addInitContianers(row, data)
  addEphemeralContianers(row, data)
  return data
end

return M
