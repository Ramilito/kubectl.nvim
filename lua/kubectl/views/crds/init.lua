local ResourceBuilder = require("kubectl.resourcebuilder")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "crds"
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "apiextensions.k8s.io", v = "v1", k = "CustomResourceDefinition" },
    plural = "customresourcedefinitions",
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "resource", long_desc = "Open resource view" },
    },
    headers = {
      "NAME",
      "GROUP",
      "KIND",
      "VERSIONS",
      "SCOPE",
      "AGE",
    },
  },

  selection = {},
}

function M.View(cancellationToken)
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
end

--- Describe a configmap
---@param name string
function M.Desc(name, _, reload)
  local def = {
    resource = "crds | " .. name,
    ft = "k8s_desc",
    url = { "describe", "crd", name },
    syntax = "yaml",
    cmd = "describe_async",
  }
  ResourceBuilder:view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.plural,
      nil,
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
  return tables.getCurrentSelection(1)
end

return M
