local BaseResource = require("kubectl.resources.base_resource")

local resource = "serviceaccounts"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "ServiceAccount" },
  url = { "{{BASE}}/api/v1/{{NAMESPACE}}serviceaccounts?pretty=false" },
  headers = {
    "NAMESPACE",
    "NAME",
    "SECRET",
    "AGE",
  },
})
