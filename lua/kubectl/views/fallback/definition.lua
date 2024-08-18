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

function M.processResource(row)
  local default_cols = {
    namespace = row.metadata.namespace,
    name = row.metadata.name,
    status = getStatus(row),
  }
  if not M.row_def then
    return default_cols
  end
  local resource = {}
  for col, value_cb in pairs(M.row_def) do
    if type(col) == "number" then
      col = value_cb
      value_cb = ""
    end
    local name = col:lower()
    local value = ""
    if (not value_cb or value_cb == "" or value_cb == nil) and default_cols[name] ~= nil then
      value = default_cols[name]
    else
      -- if def is a function, call it with the row as the argument
      if type(value_cb) == "function" and row then
        value = value_cb(row) or "blat"
      end
    end
    resource[name] = value
  end
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
      local resource = M.processResource(row)
      -- local resource = {
      --   namespace = row.metadata.namespace,
      --   name = row.metadata.name,
      --   status = getStatus(row),
      --   version = version,
      -- }
      table.insert(data, resource)
    end
  end

  return data
end

function M.getHeaders(rows)
  if M.row_def then
    return vim.tbl_keys(M.row_def)
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
    end
  end
  return headers
end

return M
