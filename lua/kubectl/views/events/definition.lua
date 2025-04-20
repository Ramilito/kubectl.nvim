local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {}

local function getLastSeen(row, currentTime)
  if row.lastTimestamp ~= vim.NIL then
    return time.since(row.lastTimestamp, true, currentTime)
  elseif row.eventTime ~= vim.NIL then
    return time.since(row.eventTime, true, currentTime)
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

  if not rows then
    return data
  end

  local currentTime = time.currentTime()

  for _, row in pairs(rows) do
    local pod = {
      namespace = row.metadata.namespace,
      ["last seen"] = getLastSeen(row, currentTime),
      type = getType(row.type),
      reason = getReason(row.reason),
      object = row.involvedObject.name,
      count = tonumber(row.count) or 0,
      message = row and row.message and row.message:gsub("\n", "") or "",
    }

    table.insert(data, pod)
  end
  return data
end

return M
