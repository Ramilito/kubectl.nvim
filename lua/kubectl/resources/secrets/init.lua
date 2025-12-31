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

-- Override Yaml with hints for base64 decode
function M.Yaml(name, ns)
  local def = {
    resource = M.definition.resource .. "_yaml",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_" .. M.definition.resource .. "_yaml",
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
  })
end

return M
