local hl = require("kubectl.actions.highlight")
local M = {
  resource = "root",
  display_name = "Root",
  ft = "k8s_root",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/pods?pretty=false" },
  hints = { { key = "<Plug>(kubectl.select)", desc = "Select" } },
  cmd = "curl",
}

function M.processRow(rows)
  local data = {
    info = {
      { name = "kubelets up:", value = "10", symbol = hl.symbols.success },
      { name = "Running pods:", value = "8", symbol = hl.symbols.success },
    },
    nodes = {
      { name = "Node1", value = "CPU: 45%, RAM: 3.2G, Pods: 4", symbol = hl.symbols.error },
      { name = "Node2", value = "CPU: 33%, RAM: 2.5G, Pods: 3", symbol = hl.symbols.error },
    },
    ["high-cpu"] = {
      { name = "pod1", value = "70%", symbol = hl.symbols.error },
      { name = "pod2", value = "90%", symbol = hl.symbols.error },
    },
    ["high-ram"] = {
      { name = "pod1", value = "40%", symbol = hl.symbols.error },
      { name = "pod2", value = "89%", symbol = hl.symbols.error },
    },
  }

  -- local temp_data = {}
  -- for _, row in pairs(rows.items) do
  --   if not temp_data[row.metadata.namespace] then
  --     temp_data[row.metadata.namespace] = {}
  --   end
  --   table.insert(temp_data[row.metadata.namespace], row)
  -- end
  -- for key, namespace in pairs(temp_data) do
  -- end

  -- table.insert(data, {
  --   info = { kubelets = getKubelets(), running_pods = getRunningPods() },
  --   nodes = {
  --     { name = "node1", cpu = "20%", ram = "50%", pods = "2" },
  --     { name = "node2", cpu = "40%", ram = "40%", pods = "20" },
  --     { name = "node3", cpu = "70%", ram = "70%", pods = "200" },
  --   },
  --   ["high-cpu"] = { { name = "pod1", cpu = "70%" }, { name = "pod2", cpu = "90%" } },
  --   ["high-ram"] = { { name = "pod1", ram = "40%" }, { name = "pod2", ram = "89%" } },
  -- })
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
