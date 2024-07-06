local M = {}
local time = require("kubectl.utils.time")

local function getData(data)
  local count = 0
  if data then
    for _ in pairs(data) do
      count = count + 1
    end
  end
  return count
end

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      type = row.type,
      data = getData(row.data),
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "TYPE",
    "DATA",
    "AGE",
  }

  return headers
end

return M
