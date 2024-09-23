local M = {
  resource = "services",
  display_name = "Services",
  ft = "k8s_services",
  url = { "{{BASE}}/api/v1/{{NAMESPACE}}services?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
    { key = "<Plug>(kubectl.portforward)", desc = "Port forward", long_desc = "Port forward" },
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
    LoadBalancer = hl.symbols.note,
    ExternalName = hl.symbols.success,
  }
  return { symbol = typeColor[type] or "", value = type }
end

local function getClusterIP(row)
  local clusterIP = row.spec.clusterIP or "<none>"
  if clusterIP == "None" then
    clusterIP = "<none>"
  end
  return clusterIP
end

local function lbIngressIPs(row)
  local ingress = row.status and row.status.loadBalancer and row.status.loadBalancer.ingress
  if not ingress then
    return {}
  end
  local result = {}
  for _, v in ipairs(ingress) do
    table.insert(result, v.ip or v.hostname)
  end
  return result
end

local function getExternalIP(row)
  local svcType = row.spec.type
  local final_res = {}

  if svcType == "ClusterIP" then
    return "<none>"
  elseif svcType == "NodePort" then
    return row.spec.externalIPs and table.concat(row.spec.externalIPs, ",") or "<none>"
  elseif svcType == "LoadBalancer" then
    local lbIPs = lbIngressIPs(row)
    if row.spec.externalIPs then
      if #lbIPs > 0 then
        vim.list_extend(final_res, lbIPs)
      end
      vim.list_extend(final_res, row.spec.externalIPs)
      return table.concat(final_res, ",")
    end
    if #lbIPs > 0 then
      vim.list_extend(final_res, lbIPs)
    end
  elseif svcType == "ExternalName" then
    table.insert(final_res, row.spec.externalName)
  end

  return table.concat(final_res, ",")
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
      ["cluster-ip"] = getClusterIP(row),
      ["external-ip"] = getExternalIP(row),
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
