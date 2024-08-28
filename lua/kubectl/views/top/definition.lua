local M = {
  resource = "top",
  display_name = "top",
  ft = "k8s_top",
  url = {},
  url_pods = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/{{NAMESPACE}}pods?pretty=false" },
  url_nodes = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/nodes?pretty=false" },
  res_type = "pods",
  hints = {
    { key = "<gp>", desc = "top-pods", long_desc = "Top pods" },
    { key = "<gn>", desc = "top-nodes", long_desc = "Top nodes" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getCpuUsage(row)
  local status = { symbol = "", value = "", sort_by = "" }
  local cpu = row.containers and row.containers[1].usage.cpu or row.usage.cpu
  status.value = cpu
  cpu = string.sub(cpu, 1, -2)
  status.sort_by = tonumber(cpu)
  if not cpu or cpu == nil or tonumber(cpu) == nil then
    return status
  end
  cpu = tonumber(cpu) / 1000000
  cpu = math.ceil(cpu)
  status.value = cpu .. "m"
  return status
end

local function getMemUsage(row)
  local status = { symbol = "", value = "", sort_by = "" }
  -- last 2 characters are "Ki"
  local size_str = row.containers and row.containers[1].usage.memory or row.usage.memory
  local unit = string.sub(size_str, -2) or "Ki"
  status.sort_by = tonumber(string.sub(size_str, 1, -3) or 0)
  if unit == "Ki" then
    unit = "Mi"
    size_str = string.sub(size_str, 1, -3)
    size_str = math.floor(tonumber(size_str) / 1024)
  end
  status.value = size_str .. unit
  vim.print("value: " .. status.value .. " sort_by: " .. status.sort_by)
  return status
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
      ["cpu-cores"] = getCpuUsage(row),
      ["mem-bytes"] = getMemUsage(row),
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "CPU-CORES",
    "MEM-BYTES",
  }
  if M.res_type == "pods" then
    table.insert(headers, 1, "NAMESPACE")
  end

  return headers
end

return M
