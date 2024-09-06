local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.top.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  definition.url = definition.urls[definition.res_type]
  definition.display_name = "top " .. definition.res_type

  ResourceBuilder:view(definition, cancellationToken, { informer = false })
  if definition.res_type == "nodes" then
    definition.get_nodes()
  end
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
