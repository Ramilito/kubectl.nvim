local events = require("kubectl.utils.events")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")
local time = require("kubectl.utils.time")
local M = {}

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

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      name = row.metadata.name,
      status = getStatus(row),
      roles = getRole(row),
      age = time.since(row.metadata.creationTimestamp),
      version = row.status.nodeInfo.kubeletVersion,
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
  }

  return headers
end

return M
