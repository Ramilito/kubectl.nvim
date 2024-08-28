local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.top.definition")
local tables = require("kubectl.utils.tables")

local M = { builder = nil }

function M.View(cancellationToken)
  M.pfs = {}
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Desc(name, ns)
  ResourceBuilder:view_float({
    resource = "desc",
    ft = "k8s_svc_desc",
    url = { "describe", "svc", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
