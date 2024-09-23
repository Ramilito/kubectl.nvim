local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = { builder = nil, pfs = {} }

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true, "svc")
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
  root_definition.setPortForwards(state.instance.extmarks, state.instance.prettyData, M.pfs)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_service_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "services/" .. name, "-n", ns })
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "services_desc_" .. name .. "_" .. ns,
    ft = "k8s_desc",
    url = { "describe", "svc", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
