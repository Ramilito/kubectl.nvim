local ResourceBuilder = require("kubectl.resourcebuilder")
local client = require("kubectl.client")
local definition = require("kubectl.views.deployments.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view_new(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if state.instance[definition.resource] then
    local table = client.get_table(definition)
    state.instance[definition.resource].processedData = table
    state.instance[definition.resource]:draw(definition, cancellationToken)
  end
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "deployments| " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "deployment", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
