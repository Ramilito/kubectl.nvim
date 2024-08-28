local M = {
  resource = "top",
  display_name = "top",
  ft = "k8s_top",
  url = {},
  urls = {
    pods = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/{{NAMESPACE}}pods?pretty=false" },
    nodes = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/nodes?pretty=false" },
  },
  res_type = "pods",
  hints = {
    { key = "<gp>", desc = "top-pods", long_desc = "Top pods" },
    { key = "<gn>", desc = "top-nodes", long_desc = "Top nodes" },
  },
  nodes = {},
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getCpuUsage(row, node)
  local status = { symbol = "", value = "", sort_by = 0 }
  local temp_val = 0
  local out_of = ""
  if row.containers then
    for _, container in pairs(row.containers) do
      local cpu = container.usage.cpu
      local cpu_val = tonumber(string.sub(cpu, 1, -2)) or 0
      temp_val = temp_val + cpu_val
    end
  elseif row.usage.cpu then
    local cpu = row.usage.cpu
    temp_val = tonumber(string.sub(cpu, 1, -2)) or 0
    out_of = node and node.status and node.status.capacity.cpu or ""
    if out_of ~= "" then
      local v = tonumber(out_of) * 1000
      local percent = math.ceil((math.ceil(temp_val / 1000000) / v) * 100) or 0
      out_of = "/" .. v .. "m (" .. percent .. "%)"
    end
  end

  status.sort_by = temp_val
  status.value = math.ceil(temp_val / 1000000) .. "m" .. out_of

  return status
end

local function getMemUsage(row, node)
  local status = { symbol = "", value = "", sort_by = "" }
  local temp_val = 0
  local out_of = ""
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
    out_of = node and node.status and node.status.capacity.memory or ""
    if out_of ~= "" then
      local v = math.floor(tonumber(string.sub(out_of, 1, -3)) / 1024) or 0
      local percent = math.ceil((math.floor(temp_val / 1024) / v) * 100)
      if v > 10240 then
        out_of = "/" .. math.floor(v / 1024) .. "Gi (" .. percent .. "%)"
      else
        out_of = "/" .. v .. "Mi (" .. percent .. "%)"
      end
    end
  end

  status.sort_by = temp_val
  local final_val = math.floor(temp_val / 1024)
  if final_val > 10240 then
    status.value = math.floor(final_val / 1024) .. "Gi" .. out_of
  else
    status.value = final_val .. "Mi" .. out_of
  end
  return status
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  for _, row in pairs(rows.items) do
    -- find node
    local node_details = ""
    if #M.nodes > 0 then
      for _, node in pairs(M.nodes) do
        if node.metadata.name == row.metadata.name and node_details == "" then
          node_details = node
        end
      end
    end
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      ["cpu-cores"] = getCpuUsage(row, node_details),
      ["mem-bytes"] = getMemUsage(row, node_details),
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

function M.get_nodes()
  if #M.nodes > 0 then
    return
  end
  local nodes_def = require("kubectl.views.nodes.definition")
  local ResourceBuilder = require("kubectl.resourcebuilder")
  ResourceBuilder:new("nodes"):setCmd(nodes_def.url, "curl"):fetchAsync(function(self)
    self:decodeJson()
    M.nodes = self.data.items
    --
    ----
  end)
end
return M
