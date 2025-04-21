local time = require("kubectl.utils.time")

local M = {}

function M.processRow(rows)
  local data = {}

  if not rows then
    return data
  end

  for _, row in ipairs(rows) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      secret = row.secrets and #row.secrets or 0,
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end
  return data
end

return M
