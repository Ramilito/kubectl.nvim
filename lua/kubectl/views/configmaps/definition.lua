local M = {
  resource = "configmaps",
  display_name = "Configmaps",
  ft = "k8s_configmaps",
  url = { "{{BASE}}/api/v1/{{NAMESPACE}}configmaps?pretty=false" },
}
local time = require("kubectl.utils.time")

--- Get the count of items in the provided data table
---@param data table
---@return number
local function getData(data)
  if not data then
    return 0
  end
  local count = 0
  for _ in pairs(data) do
    count = count + 1
  end
  return count
end

--- Process rows and transform them into a structured table
---@param rows { items: table[] }
---@return table[]
function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
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
    "DATA",
    "AGE",
  }

  return headers
end

return M
