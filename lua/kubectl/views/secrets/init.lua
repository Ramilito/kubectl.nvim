local manager = require("kubectl.resource_manager")
local tables = require("kubectl.utils.tables")

local resource = "secrets"
local M = {
  definition = {
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
      kind = M.definition.gvk.k,
      namespace = ns,
      name = name,
      output = def.syntax,
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
