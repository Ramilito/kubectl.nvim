local M = {
  resource = "services",
  display_name = "Services",
  ft = "k8s_services",
  url = { "{{BASE}}/api/v1/{{NAMESPACE}}services?pretty=false" },
  hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected service" },
    { key = "<gp>", desc = "Port forward", long_desc = "Port forward" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getPorts(ports)
  if not ports then
    return ""
  end
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
  local typeColor = {
    ClusterIP = "",
    NodePort = hl.symbols.debug,
    LoadBalancer = hl.symbols.header,
    ExternalName = hl.symbols.success,
  }
  return { symbol = typeColor[type] or "", value = type }
end

--TODO: Get externalip
---@diagnostic disable-next-line: unused-local
local function getExternalIP(spec) -- luacheck: ignore
  return ""
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      type = getType(row.spec.type),
      ["cluster-ip"] = row.spec.clusterIP,
      ["external-ip"] = getExternalIP(row.spec),
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
    "CLUSTER-IP",
    "EXTERNAL-IP",
    "PORTS",
    "AGE",
  }

  return headers
end

return M
