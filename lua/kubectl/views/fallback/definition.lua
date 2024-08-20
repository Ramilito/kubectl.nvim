local events = require("kubectl.utils.events")
local string_utils = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")
local time = require("kubectl.utils.time")
local M = {
  headers = {
    "NAMESPACE",
    "NAME",
  },
}

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
      local resource = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
      }
      if vim.tbl_contains(M.headers, "STATUS") then
        resource.status = getStatus(row)
      end
      if row.spec and row.spec.version and vim.tbl_contains(M.headers, "VERSION") then
        resource.version = row.spec.version
      end
      if row.metadata.creationTimestamp and vim.tbl_contains(M.headers, "AGE") then
        resource.age = time.since(row.metadata.creationTimestamp, true)
      end
      table.insert(data, resource)
    end
    return data
  end
end

function M.getHeaders(rows)
  local headers
  if rows.columnDefinitions then
    headers = { "NAMESPACE" }
    for _, col in pairs(rows.columnDefinitions) do
      local col_name = string.upper(col.name)
      if not headers[col_name] then
        table.insert(headers, string.upper(col_name))
      end
    end
  else
    if rows.items then
      headers = vim.deepcopy(M.headers)
      local firstItem = rows.items[1]
      if firstItem then
        if
          firstItem.status
          and (firstItem.status.conditions or firstItem.status.health)
          and not vim.tbl_contains(headers, "STATUS")
        then
          table.insert(headers, "STATUS")
        end

        if firstItem.spec and firstItem.spec.version and not vim.tbl_contains(headers, "VERSION") then
          table.insert(headers, "VERSION")
        end

        if firstItem.metadata and firstItem.metadata.creationTimestamp and not vim.tbl_contains(headers, "AGE") then
          table.insert(headers, "AGE")
        end
      end
    end
  end
  M.headers = headers
  return headers
end

return M
