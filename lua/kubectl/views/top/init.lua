local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.top.definition")
local tables = require("kubectl.utils.tables")

local M = { builder = nil }

function M.View(cancellationToken)
  definition.url = definition.urls[definition.res_type]
  definition.display_name = "top " .. definition.res_type
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken, { informer = false })
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken, { informer = false })
  end
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
