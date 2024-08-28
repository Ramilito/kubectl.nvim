local time = require("kubectl.utils.time")

local M = {
  resource = "containers",
  display_name = "",
  ft = "k8s_containers",
  url = {},
  hints = {
    { key = "<Plug>(kubectl.logs)", desc = "logs" },
    { key = "<Plug>(kubectl.select)", desc = "exec" },
  },
}

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

function M.processRow(row)
  local data = {}

  if row.spec and row.status and row.status.containerStatuses then
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
  end
  return data
end

function M.getHeaders()
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

return M
