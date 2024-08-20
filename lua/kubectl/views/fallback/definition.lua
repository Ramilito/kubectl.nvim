local events = require("kubectl.utils.events")
local string_utils = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")
local time = require("kubectl.utils.time")
local M = {}

local function getStatus(row)
  if not row.status then
    return ""
  end

  if row.status.conditions then
    local conditionMap = {}

    for _, cond in ipairs(row.status.conditions) do
      if cond.type then
        conditionMap[cond.type] = cond
      end
    end

    if tables.isEmpty(conditionMap) then
      return { symbol = events.ColorStatus("Error"), value = "Unknown" }
    end

    -- Check "Ready" condition first
    local readyCondition = conditionMap["Ready"]
    if readyCondition and readyCondition.status == "True" then
      return {
        symbol = events.ColorStatus("Ready"),
        value = readyCondition.reason or readyCondition.status,
      }
    end

    -- Check other conditions
    for _, condition in pairs(conditionMap) do
      if condition.status == "True" then
        return {
          symbol = events.ColorStatus(condition.type),
          value = condition.reason ~= "" and condition.reason or condition.type,
        }
      end
    end

    return { symbol = events.ColorStatus("Error"), value = "Unknown" }
  end

  if row.status.health then
    return { symbol = events.ColorStatus(string_utils.capitalize(row.status.health)), value = row.status.health }
  end
end

function M.processRow(rows)
  local data = {}

  -- process curl table json
  if rows.rows then
    for _, row in pairs(rows.rows) do
      local resource_vals = row.cells
      local resource = {
        namespace = row.object.metadata.namespace,
      }
      for i, val in pairs(resource_vals) do
        resource[string.lower(rows.columnDefinitions[i].name)] = val
      end
      table.insert(data, resource)
    end
    return data
  end
  -- process kubectl json
  if rows.items then
    for _, row in pairs(rows.items) do
      local version = ""
      if row.spec and row.spec.version then
        version = row.spec.version
      end
      local age
      if row.metadata.creationTimestamp then
        age = time.since(row.metadata.creationTimestamp, true)
      end
      local resource = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        status = getStatus(row),
        version = version,
        age = age,
      }
      table.insert(data, resource)
    end
    return data
  end
end

function M.getHeaders(rows)
  if rows.columnDefinitions then
    local headers = { "NAMESPACE" }
    for _, col in pairs(rows.columnDefinitions) do
      local col_name = string.upper(col.name)
      if not headers[col_name] then
        table.insert(headers, string.upper(col_name))
      end
    end
    return headers
  end
  local headers = {
    "NAMESPACE",
    "NAME",
  }
  if rows.items then
    local firstItem = rows.items[1]
    if firstItem then
      if firstItem.status and (firstItem.status.conditions or firstItem.status.health) then
        table.insert(headers, "STATUS")
      end

      if firstItem.spec and firstItem.spec.version then
        table.insert(headers, "VERSION")
      end

      if firstItem.metadata and firstItem.metadata.creationTimestamp then
        table.insert(headers, "AGE")
      end
    end
  end
  return headers
end

return M
