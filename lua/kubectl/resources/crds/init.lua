local BaseResource = require("kubectl.resources.base_resource")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local resource = "crds"

local M = BaseResource.extend({
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
})

M.selection = {}

-- Override Desc to use plural for the gvk.k
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
      context = state.context["current-context"],
      gvk = { k = M.definition.plural, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = nil,
      name = name,
    },
    reload = reload,
  })
end

return M
