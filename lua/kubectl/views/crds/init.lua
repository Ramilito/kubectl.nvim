local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.crds.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

--- Describe a configmap
---@param name string
function M.Desc(name, _, reload)
  ResourceBuilder:view_float({
    resource = "crd | " .. name,
    ft = "k8s_desc",
    url = { "describe", "crd", name },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
