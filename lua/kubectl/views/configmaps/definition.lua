local M = {}
local time = require("kubectl.utils.time")

--- Get the count of items in the provided data table
---@param data table
---@return number
local function getData(data)
  local count = 0
  if data then
    for _ in pairs(data) do
      count = count + 1
    end
  end
  return count
end

--- Process rows and transform them into a structured table
---@param rows { items: table[] }
---@return table[]
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

--- Get the headers for the processed data table
---@return string[]
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
