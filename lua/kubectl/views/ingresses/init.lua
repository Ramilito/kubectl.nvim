local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.ingresses.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "ingresses"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "networking.k8s.io", v = "v1", k = "Ingress" },
    informer = { enabled = true },
    hints = {
      { key = "<Plug>(kubectl.browse)", desc = "browse", long_desc = "Open host in browser" },
    },
    processRow = definition.processRow,
    headers = {
      "NAMESPACE",
      "NAME",
      "CLASS",
      "HOSTS",
      "ADDRESS",
      "PORTS",
      "AGE",
    },
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    builder.draw(cancellationToken)
  end
end

function M.OpenBrowser(name, ns)
  commands.run_async(
    "get_single_async",
    { kind = M.definition.gvk.k, namespace = ns, name = name, output = nil },
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

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    cmd = "describe_async",
    syntax = "yaml",
  }
  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.resource,
      ns,
      name,
      M.definition.gvk.g,
      M.definition.gvk.v,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
