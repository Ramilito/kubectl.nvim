local M = {}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getNodeSelector(row)
  local ns = row.spec.template.spec.nodeSelector
  if ns then
    local result = ""
    for key, value in pairs(ns) do
      if result ~= "" then
        result = result .. ","
      end
      result = result .. key .. "=" .. value
    end
    return result
  end
  return "<none>"
end

function M.processRow(rows)
  local data = {}
  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local status = row.status

      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        desired = status.desiredNumberScheduled or 0,
        current = status.currentNumberScheduled or 0,
        ready = M.getReady(row),
        uptodate = status.updatedNumberScheduled or 0,
        available = status.numberAvailable or 0,
        nodeselector = getNodeSelector(row),
        age = time.since(row.metadata.creationTimestamp, true),
      }

      table.insert(data, pod)
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "DESIRED",
    "CURRENT",
    "READY",
    "UPTODATE",
    "AVAILABLE",
    "NODESELECTOR",
    "AGE",
  }

  return headers
end

function M.getReady(row)
  local status = { symbol = "", value = "" }
  local numberReady = row.status.numberReady
  if numberReady then
    status.value = numberReady .. "/" .. (row.status.numberAvailable or 0)
    if numberReady == row.status.numberAvailable then
      status.symbol = hl.symbols.note
    else
      status.symbol = hl.symbols.deprecated
    end
  else
    status.symbol = hl.symbols.deprecated
    -- TODO: There should be other numbers to fetch here
    status.value = "0/0"
  end
  return status
end

return M