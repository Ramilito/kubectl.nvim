local BaseResource = require("kubectl.resources.base_resource")

local resource = "storageclasses"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "storage.k8s.io", v = "v1", k = "StorageClass" },
  headers = {
    "NAME",
    "PROVISIONER",
    "RECLAIMPOLICY",
    "VOLUMEBINDINGMODE",
    "ALLOWVOLUMEEXPANSION",
    "AGE",
  },
})
