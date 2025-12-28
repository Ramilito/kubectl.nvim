local BaseResource = require("kubectl.resources.base_resource")

local resource = "horizontalpodautoscalers"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "autoscaling", v = "v2", k = "HorizontalPodAutoscaler" },
  headers = {
    "NAMESPACE",
    "NAME",
    "REFERENCE",
    "TARGETS",
    "MINPODS",
    "MAXPODS",
    "REPLICAS",
    "AGE",
  },
})
