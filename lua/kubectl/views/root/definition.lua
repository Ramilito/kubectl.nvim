local hl = require("kubectl.actions.highlight")
local M = {
  resource = "root",
  display_name = "Root",
  ft = "k8s_root",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/pods?pretty=false" },
  hints = { { key = "<Plug>(kubectl.select)", desc = "Select" } },
  cmd = "curl",
}

local function getInfo(rows)
  local data = {}
  table.insert(data, { name = "kubelets up:", value = "10", symbol = hl.symbols.success })
  table.insert(data, { name = "Running pods:", value = "8", symbol = hl.symbols.success })

  return data
end

local function getNodes(rows)
  local data = {}
  table.insert(data, { name = "Node1", value = "CPU: 45%, RAM: 3.2G, Pods: 4", symbol = hl.symbols.error })
  table.insert(data, { name = "Node2", value = "CPU: 33%, RAM: 2.5G, Pods: 3", symbol = hl.symbols.error })
  return data
end

local function getCpu(rows)
  local data = {}
  table.insert(data, { name = "pod1", value = "70%", symbol = hl.symbols.error })
  table.insert(data, { name = "pod2", value = "90%", symbol = hl.symbols.error })
  return data
end

local function getRam(rows)
  local data = {}

  table.insert(data, { name = "pod1", value = "40%", symbol = hl.symbols.error })
  table.insert(data, { name = "pod2", value = "89%", symbol = hl.symbols.error })

  return data
end

function M.processRow(rows)
  local data = {
    info = getInfo(rows),
    nodes = getNodes(rows),
    ["high-cpu"] = getCpu(rows),
    ["high-ram"] = getRam(rows),
  }

  -- local temp_data = {}
  --   if not temp_data[row.metadata.namespace] then
  --     temp_data[row.metadata.namespace] = {}
  --   end
  --   table.insert(temp_data[row.metadata.namespace], row)
  -- end
  -- for key, namespace in pairs(temp_data) do

  return data
end

function M.getSections()
  local sections = {
    "info",
    "nodes",
    "high-cpu",
    "high-ram",
  }

  return sections
end
return M
