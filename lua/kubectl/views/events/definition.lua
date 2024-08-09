local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {}

local function getLastSeen(row)
  if row.lastTimestamp ~= vim.NIL then
    return time.since(row.lastTimestamp, true)
  elseif row.eventTime ~= vim.NIL then
    return time.since(row.eventTime, true)
  else
    return nil
  end
end

local function getType(type)
  local status = { symbol = "", value = type }
  status.symbol = events.ColorStatus(type)
  return status
end

local function getReason(reason)
  local status = { symbol = "", value = reason }
  status.symbol = events.ColorStatus(reason)
  return status
end

function M.processRow(rows)
  local data = {}

  if not rows.items then
    return data
  end
  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      lastseen = getLastSeen(row),
      type = getType(row.type),
      reason = getReason(row.reason),
      object = row.involvedObject.name,
      count = tonumber(row.count) or 0,
      message = row.message,
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "LASTSEEN",
    "TYPE",
    "REASON",
    "OBJECT",
    "COUNT",
    "MESSAGE",
  }

  return headers
end

return M
