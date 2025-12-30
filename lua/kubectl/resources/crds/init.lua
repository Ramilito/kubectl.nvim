local BaseResource = require("kubectl.resources.base_resource")
local describe_session = require("kubectl.views.describe.session")

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
function M.Desc(name, _, _)
  local gvk = { k = M.definition.plural, g = M.definition.gvk.g, v = M.definition.gvk.v }
  describe_session.view(M.definition.resource, name, nil, gvk)
end

return M
