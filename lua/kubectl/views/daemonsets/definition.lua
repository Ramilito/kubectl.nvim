local M = {}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

function M.processRow(rows)
  local data = {}
  print(vim.inspect(rows))
  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        desired = row.status.desiredNumberScheduled,
        current = row.status.currentNumberScheduled,
        ready = M.getReady(row),
        uptodate = row.status.updatedNumberScheduled,
        available = row.status.numberAvailable,
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
    status.value = numberReady .. "/" .. row.status.numberAvailable
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
