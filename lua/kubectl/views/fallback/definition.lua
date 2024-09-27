local events = require("kubectl.utils.events")
local tables = require("kubectl.utils.tables")
local time = require("kubectl.utils.time")
local M = {
  headers = {
    "NAME",
  },
  namespaced = false,
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
    local health = row.status.health.status or row.status.health
    return {
      symbol = events.ColorStatus(health),
      value = health,
    }
  end
end

function M.processRow(rows)
  local data = {}
  if not rows or (not rows.items and not rows.rows) then
    return data
  end

  -- process curl table json
  if rows.rows then
    for _, row in pairs(rows.rows) do
      local resource_vals = row.cells
      local resource = {}
      local namespace = row.object.metadata.namespace
      if namespace then
        resource.namespace = namespace
      end
      for i, val in pairs(resource_vals) do
        local res_key = string.lower(rows.columnDefinitions[i].name)
        local is_time = time.since(val)
        -- if the value parsed as time, then it's age/created at column
        if is_time then
          resource[res_key] = is_time
        else
          resource[res_key] = { value = val or "", symbol = events.ColorStatus(val) }
        end
      end
      table.insert(data, resource)
    end
    return data
  end
  -- process kubectl json
  if rows.items then
    for _, row in pairs(rows.items) do
      local resource = { name = row.metadata.name }
      if M.namespaced then
        resource.namespace = row.metadata.namespace
      end
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
  if not rows then
    return M.headers
  end

  local headers
  if rows.columnDefinitions then
    headers = {}
    if M.namespaced then
      table.insert(headers, "NAMESPACE")
    end

    for _, col in pairs(rows.columnDefinitions) do
      local col_name = string.upper(col.name)
      if not headers[col_name] then
        table.insert(headers, string.upper(col_name))
      end
    end
  elseif rows.items then
    headers = vim.deepcopy(M.headers)
    local firstItem = rows.items[1]
    if firstItem then
      if firstItem.metadata and firstItem.metadata.namespace and not vim.tbl_contains(headers, "NAMESPACE") then
        table.insert(headers, "NAMESPACE")
        M.namespaced = true
      end
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
  M.headers = headers
  return headers
end

return M
