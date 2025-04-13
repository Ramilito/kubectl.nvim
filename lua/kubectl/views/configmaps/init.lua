local ResourceBuilder = require("kubectl.resourcebuilder")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "configmaps"

---@class Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "configmap" },
    informer = { enabled = true },
    headers = {
      "NAMESPACE",
      "NAME",
      "DATA",
      "AGE",
    },
  },
}

function M.View(cancellationToken)
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
end

--- Describe a configmap
---@param name string
---@param ns string
function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = M.definition.resource .. " | " .. name,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }, {
    args = {

      state.context["current-context"],
      M.definition.resource,
      ns,
      name,
      M.definition.gvk.g,
      M.definition.gvk.v,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
