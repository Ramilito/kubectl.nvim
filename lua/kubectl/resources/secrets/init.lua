local BaseResource = require("kubectl.resources.base_resource")
local manager = require("kubectl.resource_manager")

local resource = "secrets"

local M = BaseResource.extend({
  resource = resource,
  display_name = string.upper(resource),
  ft = "k8s_" .. resource,
  gvk = { g = "", v = "v1", k = "Secret" },
  informer = { enabled = true },
  headers = {
    "NAMESPACE",
    "NAME",
    "TYPE",
    "DATA",
    "AGE",
  },
})

-- Override Desc with custom behavior for secrets (uses get_single_async instead of describe_async)
function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_secret_desc",
    syntax = "yaml",
    cmd = "get_single_async",
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "base64decode" },
    },
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      gvk = M.definition.gvk,
      namespace = ns,
      name = name,
      output = def.syntax,
    },
    reload = reload,
  })
end

return M
