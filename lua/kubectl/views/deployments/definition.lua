local M = {
  resource = "deployments",
  display_name = "Deployments",
  ft = "k8s_deployments",
  url = { "{{BASE}}/apis/apps/v1/{{NAMESPACE}}deployments?pretty=false" },
  hints = {
    { key = "<grr>", desc = "restart" },
    { key = "<gd>", desc = "desc" },
    { key = "<enter>", desc = "pods" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

function M.processRow(rows)
  local data = {}
  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = M.getReady(row),
        uptodate = row.status.updatedReplicas,
        available = row.status.availableReplicas,
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
    "READY",
    "UPTODATE",
    "AVAILABLE",
    "AGE",
  }

  return headers
end

function M.getReady(row)
  local status = { symbol = "", value = "" }
  if row.status.availableReplicas then
    status.value = row.status.readyReplicas .. "/" .. row.status.availableReplicas
    if row.status.readyReplicas == row.status.availableReplicas then
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
