local manager = require("kubectl.resource_manager")
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
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    builder.draw(cancellationToken)
  end
end

--- Describe a configmap
---@param name string
function M.Desc(name, _, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.resource,
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
