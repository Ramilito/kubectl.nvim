local BaseResource = require("kubectl.resources.base_resource")

local resource = "jobs"

return BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "batch", v = "v1", k = "Job" },
  child_view = {
    name = "pods",
    predicate = function(name)
      return "metadata.ownerReferences.name=" .. name
    end,
  },
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
  },
  headers = {
    "NAMESPACE",
    "NAME",
    "COMPLETIONS",
    "DURATION",
    "AGE",
    "CONTAINERS",
    "IMAGES",
  },
})
