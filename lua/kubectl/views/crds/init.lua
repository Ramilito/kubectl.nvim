local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.crds.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

--- Edit a configmap
---@param name string
function M.Edit(name)
  buffers.floating_buffer("k8s_crds_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "crds/" .. name })
end

--- Describe a configmap
---@param name string
function M.Desc(name, _, reload)
  ResourceBuilder:view_float({
    resource = "crds_desc_" .. name,
    reload = reload,
    ft = "k8s_desc",
    url = { "describe", "crd", name },
    syntax = "yaml",
  }, { cmd = "kubectl" })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
