local M = {
  resource = "top",
  display_name = "top",
  ft = "k8s_top",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/{{NAMESPACE}}pods?pretty=false" },
  hints = {},
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getCpuUsage(row)
  -- remove the "n" suffix
  local cpu = row.containers[1].usage.cpu or "0n"
  cpu = string.sub(cpu, 1, -2)
  cpu = tonumber(cpu) / 1000000
  cpu = math.ceil(cpu)
  return cpu .. "m"
end

local function getMemUsage(row)
  -- Function to convert between KiB, MiB, and GiB
  local units = { Ki = 1, Mi = 1024, Gi = 1024 * 1024 }
  local size_str = row.containers[1].usage.memory

  -- Extract the numeric part and the unit from the size string
  local size = tonumber(size_str:sub(1, -3))
  local unit = size_str:sub(-2)
  vim.print("size: " .. size .. " unit: " .. units[unit])

  -- Convert the size to bytes
  local size_in_bytes = size * units[unit]

  -- Determine the target unit for conversion
  local target_unit = "Ki"
  if size_in_bytes >= 1024 * 1024 then
    target_unit = "Gi"
  elseif size_in_bytes >= 1024 then
    target_unit = "Mi"
  end

  -- Convert bytes to the target unit
  vim.print("size_in_bytes: " .. size_in_bytes)
  vim.print("target_unit: " .. units[target_unit])
  local converted_size = size_in_bytes / units[target_unit]
  converted_size = math.floor(converted_size * 100 + 0.5) / 100

  -- Calculate the modulo
  local modulo = size_in_bytes % units[target_unit]

  -- Print the results
  return converted_size .. target_unit .. " " .. modulo .. unit
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
    "NAMESPACE",
    "NAME",
    "CPU-CORES",
    "MEM-BYTES",
  }

  return headers
end

return M
