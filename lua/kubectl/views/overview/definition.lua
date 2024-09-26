local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local node_def = require("kubectl.views.nodes.definition")
local top_def = require("kubectl.views.top.definition")

local M = {
  resource = "overview",
  display_name = "Overview",
  ft = "k8s_overview",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/pods?pretty=false" },
  hints = { { key = "<Plug>(kubectl.select)", desc = "Select" } },
  cmd = "curl",
}

local function getInfo(nodes, replicas)
  local data = {}
  local kubelets_up = 0
  if not nodes or not nodes.items or not replicas or not replicas.items then
    return data
  end

  for _, node in ipairs(nodes.items) do
    local status = node_def.getStatus(node)
    if status.value == "Ready" then
      kubelets_up = kubelets_up + 1
    end
  end
  local desired = 0
  local ready = 0
  if replicas then
    for _, value in ipairs(replicas.items) do
      desired = desired + tonumber(value.status.replicas)
      if value.status.readyReplicas then
        ready = ready + tonumber(value.status.readyReplicas)
      end
    end
  end
  local ready_hl = hl.symbols.success
  if ready < desired then
    ready_hl = hl.symbols.error
  end

  table.insert(data, { name = "kubelets up:", value = tostring(kubelets_up), symbol = hl.symbols.success })
  table.insert(data, { name = "Running pods:", value = tostring(ready), symbol = ready_hl })
  table.insert(data, { name = "Desired pods:", value = tostring(desired), symbol = hl.symbols.success })

  return data
end

local function getNamespaces(pods)
  local data = {}
  if not pods or not pods.items then
    return data
  end
  local namespaces = {}
  for _, pod in ipairs(pods.items) do
    local namespace = pod.metadata.namespace
    local pods_count = 0
    if namespaces[namespace] then
      pods_count = namespaces[namespace].pods_count
    end
    namespaces[namespace] = { value = namespace, pods_count = pods_count + 1 }
  end

  for key, value in pairs(namespaces) do
    table.insert(data, { name = key, value = tostring(value.pods_count) })
  end
  return data
end
local function getNodes(nodes, nodes_metrics)
  local data = {}
  local results = {}

  if not nodes or not nodes.items then
    return data
  end
  for _, node in ipairs(nodes.items) do
    local metrics = find.single(nodes_metrics.items, { "metadata", "name" }, node.metadata.name)

    local cpu_percent = top_def.getCpuPercent(metrics, node)
    local mem_percent = top_def.getMemPercent(metrics, node)

    table.insert(results, {
      name = node.metadata.name,
      value = "CPU: " .. cpu_percent.value .. "," .. "RAM: " .. mem_percent.value .. " Pods: TBD",
      sort_by = cpu_percent.sort_by + mem_percent.sort_by,
      symbol = cpu_percent.symbol,
    })
  end

  table.sort(results, function(a, b)
    return a.sort_by > b.sort_by
  end)

  for i = 1, math.min(10, #results) do
    table.insert(data, { name = results[i].name, value = results[i].value, symbol = hl.symbols.error })
  end
  return data
end

local function getCpu(nodes, pods, pods_metrics)
  local data = {}
  local results = {}
  if not pods or not pods.items then
    return data
  end
  for _, pod in ipairs(pods.items) do
    local metrics = find.single(pods_metrics.items, { "metadata", "name" }, pod.metadata.name)
    local node = find.single(nodes.items, { "metadata", "name" }, pod.spec.nodeName)
    if metrics then
      local cpu_usage = top_def.getCpuUsage(metrics)
      local pod_usage = { usage = { cpu = cpu_usage.value } }
      local result = top_def.getCpuPercent(pod_usage, node)
      table.insert(
        results,
        { name = pod.metadata.name, value = result.value, sort_by = result.sort_by, symbol = result.symbol }
      )
    end
  end

  table.sort(results, function(a, b)
    return a.sort_by > b.sort_by
  end)

  for i = 1, math.min(10, #results) do
    table.insert(data, { name = results[i].name, value = results[i].value, symbol = results[i].symbol })
  end

  return data
end

local function getRam(nodes, pods, pods_metrics)
  local data = {}
  local results = {}

  if not nodes or not nodes.items or not pods or not pods.items then
    return data
  end

  for _, pod in ipairs(pods.items) do
    local metrics = find.single(pods_metrics.items, { "metadata", "name" }, pod.metadata.name)
    local node = find.single(nodes.items, { "metadata", "name" }, pod.spec.nodeName)
    if metrics then
      local mem_usage = top_def.getMemUsage(metrics)
      local pod_usage = { usage = { memory = mem_usage.value } }
      local result = top_def.getMemPercent(pod_usage, node)

      table.insert(
        results,
        { name = pod.metadata.name, value = result.value, sort_by = result.sort_by, symbol = result.symbol }
      )
    end
  end
  table.sort(results, function(a, b)
    return a.sort_by > b.sort_by
  end)

  for i = 1, math.min(10, #results) do
    table.insert(data, { name = results[i].name, value = results[i].value, symbol = results[i].symbol })
  end

  return data
end

function M.processRow(rows)
  local nodes_metrics = rows[1]
  local nodes = rows[2]
  local pods_metrics = rows[3]
  local pods = rows[4]
  local replicas = rows[5]
  local data = {

    info = getInfo(nodes, replicas),
    nodes = getNodes(nodes, nodes_metrics),
    namespaces = getNamespaces(pods),
    ["high-cpu"] = getCpu(nodes, pods, pods_metrics),
    ["high-ram"] = getRam(nodes, pods, pods_metrics),
  }

  return data
end

function M.getSections()
  local sections = {
    "info",
    "nodes",
    "namespaces",
    "high-cpu",
    "high-ram",
  }

  return sections
end
return M
