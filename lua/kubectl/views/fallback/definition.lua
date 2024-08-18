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

function M.processResource(row, additional_cols)
  local default_cols = vim.tbl_extend("force", {
    namespace = row.metadata.namespace,
    name = row.metadata.name,
    status = getStatus(row),
  }, additional_cols)
  if not M.row_def then
    return default_cols
  end
  local resource = {}
  for _, header_table in ipairs(M.row_def) do
    local name = header_table.name:lower()
    local value = ""
    local value_cb = header_table.func
    if not value_cb and default_cols[name] ~= nil then
      value = default_cols[name]
    else
      if type(value_cb) == "function" and row then
        local ok, result = pcall(value_cb, row)
        if ok then
          value = result
        else
          value = "Error"
        end
      end
    end
    resource[name] = value
  end
  resource = vim.tbl_extend("force", default_cols, resource)
  return resource
end

function M.processRow(rows)
  local data = {}
  if rows.items then
    for _, row in pairs(rows.items) do
      local version = ""
      if row.spec and row.spec.version then
        version = row.spec.version
      end
      local age = ""
      if row.metadata.creationTimestamp then
        age = time.since(row.metadata.creationTimestamp, true)
      end
      local resource = M.processResource(row, { version = version, age = age })
      table.insert(data, resource)
    end
  end

  return data
end

function M.getHeaders(rows)
  if next(M.row_def) ~= nil then
    local headers = {}
    for _, header_table in ipairs(M.row_def) do
      table.insert(headers, header_table.name)
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
