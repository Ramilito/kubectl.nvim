local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
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

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_ingress_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "ingress/" .. name, "-n", ns })
end

function M.Desc(name, ns, reload)
  local def = {
    resource = "ingresses_desc_" .. name .. "_" .. ns,
    reload = reload,
    ft = "k8s_desc",
    url = { "describe", "ingress", name, "-n", ns },
    syntax = "yaml",
  }

  ResourceBuilder:view_float(def, { cmd = "kubectl" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
