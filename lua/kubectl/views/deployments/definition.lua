local M = {
  resource = "deployments",
  display_name = "Deployments",
  ft = "k8s_deployments",
  url = { "{{BASE}}/apis/apps/v1/{{NAMESPACE}}deployments?pretty=false" },
  hints = {
    { key = "<grr>", desc = "restart", long_desc = "Restart selected deployment" },
    { key = "<gd>", desc = "desc", long_desc = "Describe selected deployment" },
    { key = "<enter>", desc = "pods", long_desc = "Opens pods view" },
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
        ["up-to-date"] = row.status.updatedReplicas or "",
        available = row.status.availableReplicas or "",
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
    "UP-TO-DATE",
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
