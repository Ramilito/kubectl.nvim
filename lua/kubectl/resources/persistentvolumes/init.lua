local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "persistentvolumes"

---@class Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "PersistentVolume" },
    headers = {
      "NAME",
      "CAPACITY",
      "ACCESS MODES",
      "RECLAIM POLICY",
      "STATUS",
      "CLAIM",
      "STORAGE CLASS",
      "REASON",
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

function M.Desc(name, _, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. "| " .. name,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      context = state.context["current-context"],
      gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = nil,
      name = name,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
