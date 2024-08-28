local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.top.definition")
local tables = require("kubectl.utils.tables")

local M = { builder = nil }

function M.View(cancellationToken)
  definition.url = definition.url_pods
  vim.print("res_type: " .. definition.res_type)
  if definition.res_type == "nodes" then
    vim.print('in here')
    definition.url = definition.url_nodes
  end
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
