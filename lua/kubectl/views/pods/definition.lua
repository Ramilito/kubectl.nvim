local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local M = {
  resource = "pods",
  display_name = "Pods",
  ft = "k8s_pods",
  url = { "{{BASE}}/api/v1/{{NAMESPACE}}pods?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.logs)", desc = "logs", long_desc = "Shows logs for all containers in pod" },
    { key = "<Plug>(kubectl.select)", desc = "containers", long_desc = "Opens container view" },
    { key = "<Plug>(kubectl.portforward)", desc = "PF", long_desc = "View active Port forwards" },
    { key = "<Plug>(kubectl.kill)", desc = "delete pod", long_desc = "Delete pod" },
  },
}

local function getReady(row)
  local status = { symbol = "", value = "", sort_by = 0 }
  local readyCount = 0
  local containers = 0
  if row.status and row.status.containerStatuses then
    for _, value in ipairs(row.status.containerStatuses) do
      containers = containers + 1
      if value.ready then
        readyCount = readyCount + 1
      end
    end
  end
  if readyCount == containers then
    status.symbol = hl.symbols.note
  else
    status.symbol = hl.symbols.deprecated
  end
  status.value = readyCount .. "/" .. containers
  status.sort_by = (readyCount * 1000) + containers
  return status
end

--- Get restarts as a symbol
---@param containerStatuses table<table>
---@param currentTime number
---@return table
local function getRestarts(containerStatuses, currentTime)
  local restarts = { symbol = "", value = "0", sort_by = 0 }
  if not containerStatuses then
    return restarts
  end

  local restartCount = 0
  local lastState

  for _, value in ipairs(containerStatuses) do
    if value.lastState and value.lastState.terminated then
      lastState = time.since(value.lastState.terminated.finishedAt, false, currentTime)
    end
    restartCount = restartCount + value.restartCount
  end
  if lastState then
    restarts.value = string.format("%d (%s ago)", restartCount, lastState.value)
    restarts.sort_by = restartCount
    local symbol_color = restartCount > 0 and events.ColorStatus("Yellow") or ""
    restarts.symbol = symbol_color
  else
    restarts.value = tostring(restartCount)
  end
  return restarts
end

local function checkInitContainerStatus(cs, count, initCount, restartable)
  if cs.state.terminated ~= nil then
    if cs.state.terminated.exitCode == 0 then
      return ""
    end
    if cs.state.terminated.reason ~= "" then
      return "Init:" .. cs.state.terminated.reason
    end
    if cs.State.Terminated.Signal ~= 0 then
      return "Init:Signal:" .. tostring(cs.state.terminated.signal)
    end
    return "Init:ExitCode:" .. tostring(cs.state.terminated.exitCode)
  elseif restartable and cs.started ~= nil and cs.started then
    if cs.ready then
      return ""
    end
  elseif cs.state.waiting ~= nil and cs.state.waiting.reason ~= "" and cs.state.waiting.reason ~= "PodInitializing" then
    return "Init:" .. cs.state.waiting.reason
  end

  return "Init:" .. tostring(count) .. "/" .. tostring(initCount)
end

local function getInitContainerStatus(row, status)
  if not row.spec or not row.spec.initContainers then
    return status, false
  end

  local count = #row.spec.initContainers
  if count == 0 then
    return status, false
  end

  local rs = {}
  if row.spec.initContainers then
    for _, c in ipairs(row.spec.initContainers) do
      rs[c.name] = c.restartPolicy ~= nil and c.restartPolicy == "Always"
    end
  end

  if row.status and row.status.initContainerStatuses then
    for i, cs in ipairs(row.status.initContainerStatuses) do
      local s = checkInitContainerStatus(cs, i, count, rs[cs.Name])
      if s ~= "" then
        return s, true
      end
    end
  end

  return status, false
end

local function getContainerStatus(pod_status, status)
  local running = false

  -- Iterate over ContainerStatuses in reverse
  if pod_status.containerStatuses then
    for i = #pod_status.containerStatuses, 1, -1 do
      local cs = pod_status.containerStatuses[i]
      local state = cs.state

      if state.waiting and state.waiting.reason ~= "" then
        status = state.waiting.reason
      elseif state.terminated then
        if state.terminated.reason ~= "" then
          status = state.terminated.reason
        elseif state.terminated.signal ~= 0 then
          status = "Signal:" .. tostring(state.terminated.signal)
        else
          status = "ExitCode:" .. tostring(state.terminated.exitCode)
        end
      elseif cs.ready and state.running then
        running = true
      end
    end
  end

  return status, running
end

local function getPodStatus(row)
  local status = row.status.phase
  local ok

  if row.status and row.status.reason ~= nil then
    if row.deletionTimestamp ~= nil and row.status.reason == "NodeLost" then
      return { value = "Unknown", symbol = events.ColorStatus("Unknown") }
    end
    status = row.status.reason
  end

  status, ok = getInitContainerStatus(row, status)
  if ok then
    return { value = status, symbol = events.ColorStatus(status) }
  end

  status, ok = getContainerStatus(row.status, status)
  if ok and status == "Completed" then
    status = "Running"
  end

  if row.metadata.deletionTimestamp == nil then
    return { value = status, symbol = events.ColorStatus(status) }
  end

  return { value = "Terminating", symbol = events.ColorStatus("Terminating") }
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  local currentTime = time.currentTime()
  if rows and rows.items then
    for i = 1, #rows.items do
      local row = rows.items[i]
      data[i] = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = getReady(row),
        status = getPodStatus(row),
        restarts = getRestarts(row.status.containerStatuses, currentTime),
        node = row.spec.nodeName,
        age = time.since(row.metadata.creationTimestamp, true, currentTime),
      }
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "READY",
    "STATUS",
    "RESTARTS",
    "NODE",
    "AGE",
  }

  return headers
end

return M
