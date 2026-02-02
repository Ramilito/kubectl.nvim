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
  local title = M.definition.resource .. " | " .. name .. " | " .. ns

  local def = {
    resource = M.definition.resource .. "_yaml",
    ft = "k8s_secrets_yaml",
    title = title,
    syntax = "yaml",
    cmd = "get_single_async",
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "base64decode" },
    },
    panes = {
      { title = "YAML" },
    },
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_framed(def, {
    args = {
      gvk = M.definition.gvk,
      namespace = ns,
      name = name,
      output = "yaml",
    },
    recreate_func = M.Yaml,
    recreate_args = { name, ns },
  })
end

return M
