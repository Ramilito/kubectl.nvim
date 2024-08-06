local events = require("kubectl.utils.events")
local string_utils = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")
local M = {}

local function getStatus(row)
  if not row.status then
    return ""
  end

  if row.status.conditions then
    local conditions = {}

    for _, cond in ipairs(row.status.conditions) do
      if cond.type then
        conditions[cond.type] = cond
      end
    end

    if tables.isEmpty(conditions) then
      return { symbol = events.ColorStatus("Error"), value = "Unknown" }
    end

    for _, condition in pairs(conditions) do
      if condition and condition.status == "True" then
        local value = condition.reason
        if condition.reason == "" then
          value = condition.type
        end
        return { symbol = events.ColorStatus(condition.type), value = value }
      end
    end

    return { symbol = events.ColorStatus("Error"), value = "Unknown" }
  elseif row.status.health then
    return { symbol = events.ColorStatus(string_utils.capitalize(row.status.health)), value = row.status.health }
  end
end

function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      status = getStatus(row),
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "STATUS",
  }

  return headers
end

return M
