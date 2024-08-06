local events = require("kubectl.utils.events")
local string_utils = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")
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
  for _, row in pairs(rows.items) do
    local version = ""
    if row.spec and row.spec.version then
      version = row.spec.version
    end
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      status = getStatus(row),
      version = version,
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders(rows)
  local headers = {
    "NAMESPACE",
    "NAME",
  }
  if rows.items[1].status and (rows.items[1].status.conditions or rows.items[1].status.health) then
    table.insert(headers, "STATUS")
  end

  if rows.items[1].spec and rows.items[1].spec.version then
    table.insert(headers, "VERSION")
  end
  return headers
end

return M
