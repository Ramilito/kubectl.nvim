local BaseResource = require("kubectl.resources.base_resource")
local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")

local resource = "ingresses"

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "networking.k8s.io", v = "v1", k = "Ingress" },
  hints = {
    { key = "<Plug>(kubectl.browse)", desc = "browse", long_desc = "Open host in browser" },
  },
  headers = {
    "NAMESPACE",
    "NAME",
    "CLASS",
    "HOSTS",
    "ADDRESS",
    "PORTS",
    "AGE",
  },
})

function M.OpenBrowser(name, ns)
  commands.run_async(
    "get_single_async",
    { gvk = M.definition.gvk, namespace = ns, name = name, output = nil },
    function(data)
      local builder = manager.get_or_create(M.definition.resource .. "_browser")
      if not builder then
        return
      end

      builder.data = data
      builder.decodeJson()
      local port = ""
      if
        builder.data.spec.rules
        and builder.data.spec.rules[1]
        and builder.data.spec.rules[1].http
        and builder.data.spec.rules[1].http.paths
        and builder.data.spec.rules[1].http.paths[1]
        and builder.data.spec.rules[1].http.paths[1].backend
      then
        local backend = builder.data.spec.rules[1].http.paths[1].backend
        port = backend.service.port.number or backend.servicePort or "80"
      end

      -- determine host
      local host = ""
      if builder.data.spec.rules and builder.data.spec.rules[1] and builder.data.spec.rules[1].host then
        host = builder.data.spec.rules[1].host
      else
        if builder.data.status and builder.data.status.loadBalancer and builder.data.status.loadBalancer.ingress then
          local ingress = builder.data.status.loadBalancer.ingress[1]
          if ingress.hostname then
            host = ingress.hostname
          elseif ingress.ip then
            host = ingress.ip
          end
        else
          return
        end
      end
      local proto = port == "443" and "https" or "http"
      local url
      if port ~= "443" and port ~= "80" then
        url = string.format("%s://%s:%s", proto, host, port)
      else
        url = string.format("%s://%s", proto, host)
      end
      vim.ui.open(url)
    end
  )
end

return M
