local BaseResource = require("kubectl.resources.base_resource")

local resource = "namespaces"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "Namespace" },
  child_view = {
    name = "pods",
    predicate = function(name)
      return "metadata.namespace=" .. name
    end,
  },
  headers = {
    "NAME",
    "STATUS",
    "AGE",
  },
})
