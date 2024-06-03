local time = require("kubectl.utils.time")

local M = {}
function M.processRow(rows)
  local data = { { name = "All", status = "", age = "" } }

  for _, row in pairs(rows.items) do
    local pod = {
      name = row.metadata.name,
      status = row.status.phase,
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end

  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "STATUS",
    "AGE",
  }

  return headers
end

return M
