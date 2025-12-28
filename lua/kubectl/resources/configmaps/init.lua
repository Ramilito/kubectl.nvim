local BaseResource = require("kubectl.resources.base_resource")

local resource = "configmaps"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "ConfigMap" },
  informer = { enabled = true },
  headers = {
    "NAMESPACE",
    "NAME",
    "DATA",
    "AGE",
  },
})
