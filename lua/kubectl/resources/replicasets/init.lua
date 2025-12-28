local BaseResource = require("kubectl.resources.base_resource")

local resource = "replicasets"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "apps", v = "v1", k = "ReplicaSet" },
  child_view = {
    name = "pods",
    predicate = function(name)
      return "metadata.ownerReferences.name=" .. name
    end,
  },
  hints = {
    { key = "<Plug>(kubectl.set_image)", desc = "set image", long_desc = "Change replicaset image" },
    { key = "<Plug>(kubectl.rollout_restart)", desc = "restart", long_desc = "Restart selected replicaset" },
    { key = "<Plug>(kubectl.scale)", desc = "scale", long_desc = "Scale replicas" },
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
  },
  headers = {
    "NAMESPACE",
    "NAME",
    "DESIRED",
    "CURRENT",
    "READY",
    "AGE",
    "CONTAINERS",
    "IMAGES",
    "SELECTOR",
  },
})
