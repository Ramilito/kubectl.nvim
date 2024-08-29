local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.crds.definition")
local tables = require("kubectl.utils.tables")

local M = { builder = nil }

function M.View(cancellationToken)
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Draw(cancellationToken)
  M.builder = M.builder:draw(definition, cancellationToken)
end

--- Edit a configmap
---@param name string
function M.Edit(name)
  buffers.floating_buffer("k8s_crds_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "crds/" .. name })
end

--- Describe a configmap
---@param name string
function M.Desc(name)
  ResourceBuilder:view_float({
    resource = "desc",
    ft = "k8s_crds_desc",
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
