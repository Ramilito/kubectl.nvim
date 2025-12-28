local BaseResource = require("kubectl.resources.base_resource")
local pf_action = require("kubectl.actions.portforward")
local pf_view = require("kubectl.views.portforward")

local resource = "services"
local gvk = { g = "", v = "v1", k = "Service" }

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = gvk,
  child_view = {
    name = "pods",
    predicate = function(name, ns)
      local client = require("kubectl.client")
      local svc = client.get_single(vim.json.encode({ gvk = gvk, namespace = ns, name = name, output = "Json" }))

      local svc_decoded = vim.json.decode(svc)
      if svc_decoded.spec.type == "ExternalName" then
        vim.notify(
          "Service " .. name .. " in namespace " .. ns .. " is of type ExternalName, no pods to show.",
          vim.log.levels.WARN
        )
        return ""
      end

      local labels = svc_decoded.spec.selector
      local parts = {}
      for k, v in pairs(labels) do
        table.insert(parts, ("metadata.labels.%s=%s"):format(k, v))
      end

      return table.concat(parts, ",")
    end,
  },
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
    { key = "<Plug>(kubectl.portforward)", desc = "Port forward", long_desc = "Port forward" },
  },
  headers = {
    "NAMESPACE",
    "NAME",
    "TYPE",
    "CLUSTER-IP",
    "EXTERNAL-IP",
    "PORTS",
    "AGE",
  },
})

function M.onBeforeDraw(builder)
  local pfs = pf_view.getPFRows(string.lower(M.definition.gvk.k))
  builder.extmarks_extra = {}
  pf_view.setPortForwards(builder.extmarks_extra, builder.prettyData, pfs)
end

function M.PortForward(name, ns)
  pf_action.portforward("service", M.definition.gvk, name, ns)
end

return M
