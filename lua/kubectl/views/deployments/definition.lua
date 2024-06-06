local M = {}
local time = require("kubectl.utils.time")

function M.processRow(rows)
  local data = {}
  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = M.getReady(row),
        uptodate = row.status.updatedReplicas,
        available = row.status.availableReplicas,
        age = time.since(row.metadata.creationTimestamp),
      }

      table.insert(data, pod)
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "READY",
    "UPTODATE",
    "AVAILABLE",
    "AGE",
  }

  return headers
end

function M.getReady(row)
  if row.status.availableReplicas then
    return row.status.readyReplicas .. "/" .. row.status.availableReplicas
  end
  return "nil"
end

return M
