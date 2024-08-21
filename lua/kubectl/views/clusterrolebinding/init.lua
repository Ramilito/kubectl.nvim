local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.clusterrolebinding.definition")
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

function M.Edit(name)
  buffers.floating_buffer("k8s_clusterrolebinding_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "clusterrolebinding/" .. name })
end

function M.Desc(name)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_clusterrolebinding_desc", name, "yaml")
    :setCmd({ "describe", "clusterrolebinding", name })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:setContentRaw()
      end)
    end)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
