local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.top-nodes.definition")
local tables = require("kubectl.utils.tables")
local top_definition = require("kubectl.views.top.definition")

local M = {}

function M.View(cancellationToken)
  definition.get_nodes()
  top_definition.res_type = "nodes"
  ResourceBuilder:view(definition, cancellationToken, { informer = false })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
