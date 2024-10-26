local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.clusterrolebinding.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.Desc(name, _, reload)
  ResourceBuilder:view_float({
    resource = "clusterrolebinding_desc_" .. name,
    ft = "k8s_desc",
    url = { "describe", "clusterrolebinding", name },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
