local BaseResource = require("kubectl.resources.base_resource")

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

return M
