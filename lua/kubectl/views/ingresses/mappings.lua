local ingresses_view = require("kubectl.views.ingresses")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.browse)"] = {
    noremap = true,
    silent = true,
    desc = "Open host in browser",
    callback = function()
      local name, ns = ingresses_view.getCurrentSelection()
      local resource = tables.find_resource(state.instance.data, name, ns)
      if not resource then
        return
      end
      -- determine port
      local port = ""
      if
        resource.spec.rules
        and resource.spec.rules[1]
        and resource.spec.rules[1].http
        and resource.spec.rules[1].http.paths
        and resource.spec.rules[1].http.paths[1]
        and resource.spec.rules[1].http.paths[1].backend
      then
        local backend = resource.spec.rules[1].http.paths[1].backend
        port = backend.service.port.number or backend.servicePort or "80"
      end

      -- determine host
      local host = ""
      if resource.spec.rules and resource.spec.rules[1] and resource.spec.rules[1].host then
        host = resource.spec.rules[1].host
      else
        if resource.status and resource.status.loadBalancer and resource.status.loadBalancer.ingress then
          local ingress = resource.status.loadBalancer.ingress[1]
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
    end,
  },
}
function M.register()
  mappings.map_if_plug_not_set("n", "gx", "<Plug>(kubectl.browse)")
end

return M
