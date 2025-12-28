local BaseResource = require("kubectl.resources.base_resource")

local resource = "persistentvolumeclaims"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "PersistentVolumeClaim" },
  child_view = {
    name = "persistentvolumes",
    predicate = function(name)
      return "spec.claimRef.name=" .. name
    end,
  },
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "Go to PVs", long_desc = "Go to the PV of the selected PVC" },
  },
  headers = {
    "NAMESPACE",
    "NAME",
    "STATUS",
    "VOLUME",
    "CAPACITY",
    "ACCESS MODES",
    "STORAGE CLASS",
    "AGE",
  },
})
