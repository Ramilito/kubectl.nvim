local hl = require("kubectl.actions.highlight")
local M = { res_type = "pods", nodes = {} }

function M.getHl(percent)
  local symbol
  if percent < 80 then
    symbol = hl.symbols.note
  elseif percent < 90 then
    symbol = hl.symbols.warning
  else
    symbol = hl.symbols.error
  end
  return symbol
end

function M.split_num_unit(mem)
  local num = tonumber(string.sub(mem, 1, -3)) or 0
  local unit = string.sub(mem, -2) or "Ki"
  return num, unit
end

function M.get_ki_val(mem)
  local mem_val, unit = M.split_num_unit(mem)
  if unit == "Mi" then
    mem_val = math.floor(mem_val * 1024)
  end
  return mem_val
end

function M.kib_to_mib_or_gib(mem)
  local final_val = math.ceil(mem / 1024)
  local unit = "Mi"
  if final_val > 10240 then
    final_val = math.floor(final_val / 1024)
    unit = "Gi"
  end
  return final_val, unit
end

function M.getCpuUsage(row)
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

function M.getCpuPercent(row, node)
  local status = { symbol = "", value = "", sort_by = 0 }
  if not row or not row.usage or not row.usage.cpu then
    return status
  end
  local tmp_cpu
  if string.sub(row.usage.cpu, -1) == "n" then
    tmp_cpu = M.getCpuUsage(row)
  else
    tmp_cpu = { value = row.usage.cpu }
  end

  local cpu = tonumber(string.sub(tmp_cpu.value, 1, -2)) or 0
  local out_of = node and node.status and node.status.allocatable and node.status.allocatable.cpu
  if out_of ~= nil and cpu ~= nil then
    out_of = string.sub(out_of, 1, -2)
    local total = tonumber(out_of)
    if total ~= nil then
      local percent = math.ceil((cpu / total) * 100) or 0
      status.sort_by = percent
      status.value = percent .. "%"
      status.symbol = M.getHl(percent)
    end
  end

  return status
end

function M.getMemUsage(row)
  local status = { symbol = "", value = "", sort_by = "" }
  local temp_val = 0
  if row.containers then
    for _, container in pairs(row.containers) do
      local mem = container.usage.memory
      temp_val = temp_val + M.get_ki_val(mem)
    end
  elseif row.usage.memory then
    local mem = row.usage.memory
    temp_val = tonumber(string.sub(mem, 1, -3)) or 0
  end

  status.sort_by = temp_val
  local final_val, unit = M.kib_to_mib_or_gib(temp_val)
  status.value = final_val .. unit
  return status
end

function M.getMemPercent(row, node)
  local status = { symbol = "", value = "", sort_by = 0 }
  if not row or not row.usage or not row.usage.memory then
    return status
  end
  local mem = M.get_ki_val(row.usage.memory)
  local out_of = node and node.status and node.status.capacity.memory or ""
  if out_of ~= "" then
    local total = M.get_ki_val(out_of)
    local percent = math.ceil((mem / total) * 100)
    status.value = percent .. "%"
    status.symbol = M.getHl(percent)
    status.sort_by = percent
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
    if #M.nodes > 0 and M.res_type == "nodes" then
      for _, node in pairs(M.nodes) do
        if node.metadata.name == row.metadata.name and node_details == "" then
          node_details = node
        end
      end
    end
    local res = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      ["cpu-cores"] = M.getCpuUsage(row),
      ["mem-bytes"] = M.getMemUsage(row),
      ["cpu-%"] = M.getCpuPercent(row, node_details),
      ["mem-%"] = M.getMemPercent(row, node_details),
    }

    table.insert(data, res)
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
  else
    table.insert(headers, 3, "CPU-%")
    table.insert(headers, 5, "MEM-%")
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
  end)
end

return M
