local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local node_def = require("kubectl.views.nodes.definition")
local top_def = require("kubectl.views.top.definition")

local M = {
  resource = "root",
  display_name = "Root",
  ft = "k8s_root",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/pods?pretty=false" },
  hints = { { key = "<Plug>(kubectl.select)", desc = "Select" } },
  cmd = "curl",
}

local function getInfo(nodes, pods)
  local data = {}
  local kubelets_up = 0
  for _, node in ipairs(nodes.items) do
    local status = node_def.getStatus(node)
    if status.value == "Ready" then
      kubelets_up = kubelets_up + 1
    end
  end

  table.insert(data, { name = "kubelets up:", value = tostring(kubelets_up), symbol = hl.symbols.success })
  table.insert(data, { name = "Running pods:", value = tostring(#pods.items), symbol = hl.symbols.success })

  return data
end

local function getNodes(nodes, nodes_metrics)
  local data = {}
  for _, node in ipairs(nodes.items) do
    local metrics = find.single(nodes_metrics.items, { "metadata", "name" }, node.metadata.name)

    local cpu_percent = top_def.getCpuPercent(metrics, node)
    local mem_percent = top_def.getMemPercent(metrics, node)

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

  local data = {
    info = getInfo(nodes, pods_metrics),
    nodes = getNodes(nodes, nodes_metrics),
    ["high-cpu"] = getCpu(rows[2]),
    ["high-ram"] = getRam(rows[2]),
  }

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
