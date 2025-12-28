local BaseResource = require("kubectl.resources.base_resource")

local resource = "clusterroles"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "rbac.authorization.k8s.io", v = "v1", k = "ClusterRole" },
  informer = { enabled = true },
  headers = {
    "NAME",
    "AGE",
  },
})
