local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.deployments.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view_new(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if state.instance[definition.resource] then
    state.instance[definition.resource]:draw(definition, cancellationToken)
  end
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float_new({
    resource = "deployments| " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
    resource_name = "Deployment",
    ns = ns,
    name = name,
    group = definition.group,
    version = definition.version,
  }, { reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
