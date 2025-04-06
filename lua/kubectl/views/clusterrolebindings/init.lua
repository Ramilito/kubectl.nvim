local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.clusterrolebindings.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "clusterrolebindings"

---@class Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "rbac.authorization.k8s.io", v = "v1", k = "clusterrolebinding" },
    informer = { enabled = true },
    processRow = definition.processRow,
    headers = {
      "NAME",
      "ROLE",
      "SUBJECT-KIND",
      "SUBJECTS",
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

function M.Desc(name, _, reload)
  ResourceBuilder:view_float(
    {
      resource = M.definition.resource .. " | " .. name,
      ft = "k8s_desc",
      syntax = "yaml",
      cmd = "describe_async",
    },
    {
      args = {
        state.context["current-context"],
        M.definition.resource,
        nil,
        name,
        M.definition.gvk.g,
      },
      reload = reload,
    }
  )
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
