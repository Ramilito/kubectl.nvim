local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.deployments.definition")
local tables = require("kubectl.utils.tables")

local M = {
  builder = nil,
}

function M.View(cancellationToken)
  if M.builder then
    M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Draw(cancellationToken)
  M.builder:view(definition, cancellationToken)
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_deployment_desc", name, "yaml")
    :setCmd({ "describe", "deployment", name, "-n", ns })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:setContentRaw()
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_deployment_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "deployments/" .. name, "-n", ns })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
