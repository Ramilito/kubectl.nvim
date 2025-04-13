local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.secrets.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "secrets"
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "secret" },
    informer = { enabled = true },
    headers = {
      "NAMESPACE",
      "NAME",
      "TYPE",
      "DATA",
      "AGE",
    },
    processRow = definition.processRow,
  },
}

function M.View(cancellationToken)
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_secret_desc",
    url = { "get", "secret", name, "-n", ns, "-o", "yaml" },
    syntax = "yaml",
    cmd = "describe_async",
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "base64decode" },
    },
  }

  ResourceBuilder:view_float(def, {
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
