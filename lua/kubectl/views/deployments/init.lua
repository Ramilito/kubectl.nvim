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

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
