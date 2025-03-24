local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.top_pods.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken, { informer = false })
end

function M.Draw(_) end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
