local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.ingresses.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.Desc(name, ns, reload)
  local def = {
    resource = "ingresses | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "ingress", name, "-n", ns },
    syntax = "yaml",
  }

  ResourceBuilder:view_float(def, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
