local M = {}

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      lastseen = row.lastTimestamp,
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
