local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local top_def = require("kubectl.views.top.definition")
-- local logger = require("kubectl.utils.logging")
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

local function getNodes(nodes, nodes_metrics)
  local data = {}
  for index, node in ipairs(nodes.items) do
    local metrics = find.single(nodes_metrics.items, { "metadata", "name" }, node.metadata.name)
    local metadata = node.metadata
    local status = node.status
    local conditions = node.conditions

    local cpu_percent = top_def.getCpuPercent(metrics, node)
    local mem_percent = top_def.getCpuPercent(metrics, node)
    -- local total_cpu = metrics.usage.cpu / status.allocatable.cpu
    -- local total_mem = metrics.usage.memory / status.allocatable.memory

    table.insert(data, {
      name = node.metadata.name,
      value = "CPU: " .. cpu_percent.value .. "," .. "RAM: " .. mem_percent.value .. " Pods: 4",
      symbol = hl.symbols.error,
    })
  end
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
  local nodes_metrics = rows[1]
  local nodes = rows[2]
  local pods_metrics = rows[3]

  -- vim.print(node_rows)
  local data = {
    info = getInfo(rows),
    nodes = getNodes(nodes, nodes_metrics),
    ["high-cpu"] = getCpu(rows[2]),
    ["high-ram"] = getRam(rows[2]),
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
