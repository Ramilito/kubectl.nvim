local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local M = {}

local function getReady(row)
  local status = { symbol = "", value = "" }
  local readyCount = 0
  local containers = 0
  if row.status.containerStatuses then
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
  return status
end

local function getRestarts(containerStatuses, currentTime)
  if not containerStatuses then
    return 0
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
    return string.format("%d (%s ago)", restartCount, lastState.value)
  else
    return restartCount
  end
end

local function getPodStatus(phase)
  local status = { symbol = events.ColorStatus(phase), value = phase }
  return status
end

function M.getPortForwards(marks, data, port_forwards)
  for _, pf in ipairs(port_forwards) do
    for row, line in ipairs(data) do
      local col = line:find(pf.resource, 1, true)

      if col then
        local mark = {
          row = row - 1,
          start_col = col + #pf.resource - 1,
          end_col = col + #pf.resource - 1 + 3,
          virt_text = { { " ⇄ ", hl.symbols.success } },
          virt_text_pos = "overlay",
        }
        table.insert(marks, #marks, mark)
      end
    end
  end
  return marks
end

function M.processRow(rows)
  local data = {}
  local currentTime = time.currentTime()
  if rows and rows.items then
    for i = 1, #rows.items do
      local row = rows.items[i]
      data[i] = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = getReady(row),
        status = getPodStatus(row.status.phase),
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
