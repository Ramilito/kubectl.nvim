local BaseResource = require("kubectl.resources.base_resource")
local set_image = require("kubectl.actions.set_image")

local resource = "deployments"
local gvk = { g = "apps", v = "v1", k = "Deployment" }

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = gvk,
  child_view = {
    name = "pods",
    predicate = function(name, ns)
      local client = require("kubectl.client")
      local deploy = client.get_single(vim.json.encode({ gvk = gvk, namespace = ns, name = name, output = "Json" }))

      local deploy_decoded = vim.json.decode(deploy)

      local labels = deploy_decoded.spec.selector.matchLabels
      local parts = {}
      for k, v in pairs(labels) do
        table.insert(parts, ("metadata.labels.%s=%s"):format(k, v))
      end

      return table.concat(parts, ",")
    end,
  },
  hints = {
    { key = "<Plug>(kubectl.set_image)", desc = "set image", long_desc = "Change deployment image" },
    { key = "<Plug>(kubectl.rollout_restart)", desc = "restart", long_desc = "Restart selected deployment" },
    { key = "<Plug>(kubectl.scale)", desc = "scale", long_desc = "Scale replicas" },
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
  },
  headers = {
    "NAMESPACE",
    "NAME",
    "READY",
    "UP-TO-DATE",
    "AVAILABLE",
    "AGE",
  },
})

function M.SetImage(name, ns)
  set_image.set_image("deployment", M.definition.gvk, name, ns)
end

return M
