local definition = require("kubectl.views.jobs.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "jobs"

local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "batch", v = "v1", k = "Job" },
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "COMPLETIONS",
      "DURATION",
      "AGE",
      "CONTAINERS",
      "IMAGES",
      "SELECTOR",
    },
		processRow = definition.processRow,
  },
}

function M.View(cancellationToken)
  definition.owner = {}
  M.definition.display_name = "Jobs"

  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if definition.owner.name then
    M.definition.display_name = "Jobs" .. "(" .. definition.owner.ns .. "/" .. definition.owner.name .. ")"
  end

  local builder = manager.get(M.definition.resource)
  if builder then
    builder.draw(cancellationToken)
  end
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
  -- ResourceBuilder:view_float(, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
