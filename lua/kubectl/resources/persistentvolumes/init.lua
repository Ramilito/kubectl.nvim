local BaseResource = require("kubectl.resources.base_resource")

local resource = "persistentvolumes"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "PersistentVolume" },
  headers = {
    "NAME",
    "CAPACITY",
    "ACCESS MODES",
    "RECLAIM POLICY",
    "STATUS",
    "CLAIM",
    "STORAGE CLASS",
    "REASON",
    "AGE",
  },
})
