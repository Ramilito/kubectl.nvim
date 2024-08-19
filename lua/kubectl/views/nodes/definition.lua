local events = require("kubectl.utils.events")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")
local time = require("kubectl.utils.time")
local M = {
  resource = "nodes",
  display_name = "Nodes",
  ft = "k8s_nodes",
  url = { "{{BASE}}/api/v1/nodes?pretty=false" },
  hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected node" },
    { key = "<gC>", desc = "cordon", long_desc = "Cordon selected node" },
    { key = "<gU>", desc = "uncordon", long_desc = "UnCordon selected node" },
    { key = "<gR>", desc = "drain", long_desc = "Drain selected node" },
  },
}

-- Define the custom match function for prefix and suffix
local function match_prefix_suffix(key, _, prefix, suffix)
  return key:match("^" .. prefix) or key:match(suffix .. "$")
end

local function getRole(row)
  local key, _ = find.dictionary(row.metadata.labels, function(key, value)
    return match_prefix_suffix(key, value, find.escape("node-role.kubernetes.io/"), find.escape("kubernetes.io/role"))
  end)

  if key then
    --TODO: Not sure if this handles the second kubernetes.io/role match
    local role = vim.split(key, "/")
    if #role == 2 then
      return role[2]
    end
  end
  return ""
end

local nodeConditions = {
  NodeReady = "Ready",
  NodeMemoryPressure = "MemoryPressure",
  NodeDiskPressure = "DiskPressure",
  NodePIDPressure = "PIDPressure",
  NodeNetworkUnavailable = "NetworkUnavailable",
}

local function getStatus(row)
  local conditions = {}
  local exempt = row.spec.unschedulable

  for _, cond in ipairs(row.status.conditions) do
    if cond.type then
      conditions[cond.type] = cond
    end
  end

  if tables.isEmpty(conditions) then
    return { symbol = events.ColorStatus("Error"), value = "Unknown" }
  end

  if exempt then
    return { symbol = hl.symbols.warning, value = "SchedulingDisabled" }
  end

  local ready = conditions[nodeConditions.NodeReady]
  if ready and ready.status == "True" then
    return { symbol = hl.symbols.success, value = nodeConditions.NodeReady }
  end
end

local function getIPs(addrs)
  local iIP, eIP
  for _, value in ipairs(addrs) do
    if value.type == "InternalIP" then
      iIP = value.address
    elseif value.type == "ExternalIP" then
      eIP = value.address
    end
  end
  if not eIP then
    eIP = "<none>"
  end
  return iIP, eIP
end

function M.processRow(rows)
  local data = {}
  if not rows or not rows.items then
    return data
  end

  for _, row in pairs(rows.items) do
    local iIP, eIP = getIPs(row.status.addresses)
    local pod = {
      name = row.metadata.name,
      status = getStatus(row),
      roles = getRole(row),
      age = time.since(row.metadata.creationTimestamp),
      version = row.status.nodeInfo.kubeletVersion,
      ["internal-ip"] = iIP,
      ["external-ip"] = eIP,
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "STATUS",
    "ROLES",
    "AGE",
    "VERSION",
    "INTERNAL-IP",
    "EXTERNAL-IP",
  }

  return headers
end

return M
