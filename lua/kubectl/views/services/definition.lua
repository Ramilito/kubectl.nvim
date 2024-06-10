local M = {}
local time = require("kubectl.utils.time")

local function getPorts(ports)
  local string_ports = ""
  for index, value in ipairs(ports) do
    string_ports = string_ports .. value.port .. "/" .. value.protocol

    if index < #ports then
      string_ports = string_ports .. ","
    end
  end
  return string_ports
end

local function getType(type)
  return type
end

--TODO: Get externalip
local function getExternalIP(spec)
  return ""
end

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      type = getType(row.spec.type),
      clusterip = row.spec.clusterIP,
      externalip = getExternalIP(row.spec),
      ports = getPorts(row.spec.ports),
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
    "TYPE",
    "CLUSTERIP",
    "EXTERNALIP",
    "PORTS",
    "AGE",
  }

  return headers
end

return M
