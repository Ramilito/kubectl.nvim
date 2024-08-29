local M = {
  resource = "top",
  display_name = "top",
  ft = "k8s_top",
  url = {},
  url_pods = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/{{NAMESPACE}}pods?pretty=false" },
  url_nodes = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/nodes?pretty=false" },
  res_type = "pods",
  hints = {
    { key = "<Plug>(kubectl.top_pods)", desc = "top-pods", long_desc = "Top pods" },
    { key = "<Plug>(kubectl.top_nodes)", desc = "top-nodes", long_desc = "Top nodes" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getCpuUsage(row)
  local status = { symbol = "", value = "", sort_by = 0 }
  local temp_val = 0
  if row.containers then
    for _, container in pairs(row.containers) do
      local cpu = container.usage.cpu
      local cpu_val = tonumber(string.sub(cpu, 1, -2)) or 0
      temp_val = temp_val + cpu_val
    end
  elseif row.usage.cpu then
    local cpu = row.usage.cpu
    temp_val = tonumber(string.sub(cpu, 1, -2)) or 0
  end

  status.sort_by = temp_val
  status.value = math.ceil(temp_val / 1000000) .. "m"
  return status
end

local function getMemUsage(row)
  local status = { symbol = "", value = "", sort_by = "" }
  local temp_val = 0
  if row.containers then
    for _, container in pairs(row.containers) do
      local mem = container.usage.memory
      local unit = string.sub(mem, -2) or "Ki"
      local mem_val = tonumber(string.sub(mem, 1, -3)) or 0
      if unit == "Mi" then
        mem_val = math.floor(mem_val * 1024)
      end
      temp_val = temp_val + mem_val
    end
  elseif row.usage.memory then
    local mem = row.usage.memory
    temp_val = tonumber(string.sub(mem, 1, -3)) or 0
  end

  status.sort_by = temp_val
  local final_val = math.floor(temp_val / 1024)
  if final_val > 10240 then
    status.value = math.floor(final_val / 1024) .. "Gi"
  else
    status.value = final_val .. "Mi"
  end
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
