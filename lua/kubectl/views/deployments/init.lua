local ResourceBuilder = require("kubectl.resourcebuilder")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local time = require("kubectl.utils.time")

local resource = "deployments"
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "apps", v = "v1", k = "deployment" },
    informer = { enabled = true },
    hints = {
      { key = "<Plug>(kubectl.set_image)", desc = "set image", long_desc = "Change deployment image" },
      { key = "<Plug>(kubectl.rollout_restart)", desc = "restart", long_desc = "Restart selected deployment" },
      { key = "<Plug>(kubectl.scale)", desc = "scale", long_desc = "Scale replicas" },
      { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "READY",
      "UP-TO-DATE",
      "AVAILABLE",
      "AGE",
    },
  },
}

function M.View(cancellationToken)
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if state.instance[M.definition.resource] then
    state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
  end
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }
  ResourceBuilder:view_float(def, { args = { M.definition.resource, ns, name, M.definition.gvk.g }, reload = reload })


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
        ["up-to-date"] = row.status and row.status.updatedReplicas or 0,
        available = row.status and row.status.availableReplicas or 0,
        age = time.since(row.metadata.creationTimestamp, true),
      }

      table.insert(data, pod)
    end
  end
  return data
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
