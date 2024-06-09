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

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      lastseen = getLastSeen(row),
      type = row.type,
      reason = row.reason,
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
