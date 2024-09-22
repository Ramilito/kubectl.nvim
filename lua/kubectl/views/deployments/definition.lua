local M = {
  resource = "deployments",
  display_name = "Deployments",
  ft = "k8s_deployments",
  url = { "{{BASE}}/apis/apps/v1/{{NAMESPACE}}deployments?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.rollout_restart)", desc = "restart", long_desc = "Restart selected deployment" },
    { key = "<Plug>(kubectl.scale)", desc = "scale", long_desc = "Scale replicas" },
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        ready = M.getReady(row),
        ["up-to-date"] = row.status.updatedReplicas or 0,
        available = row.status.availableReplicas or 0,
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
  local status = { symbol = "", value = "", sort_by = 0 }
  local available = tonumber(row.status and (row.status.availableReplicas or row.status.readyReplicas) or "0")
  local unavailable = tonumber(row.status and row.status.unavailableReplicas or "0")
  local replicas = tonumber(row.spec.replicas or (row.status and row.status.replicas) or "0")

  if available == replicas and unavailable == 0 then
    status.symbol = hl.symbols.note
  else
    status.symbol = hl.symbols.deprecated
  end

  status.value = available .. "/" .. replicas
  status.sort_by = (available * 1000) + replicas
  return status
end

return M
