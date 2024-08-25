local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.cronjobs.definition")
local tables = require("kubectl.utils.tables")

local M = {
  builder = nil,
}

function M.View(cancellationToken)
  vim.print("viewing cronjobs")
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Draw(cancellationToken)
  vim.print("drawing cronjobs")
  M.builder = M.builder:draw(definition, cancellationToken)
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_cronjob_desc", name, "yaml")
    :setCmd({ "describe", "cronjob", name, "-n", ns })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        vim.print("setting content raw cronjobs")
        self:setContentRaw()
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_cronjob_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "cronjobs/" .. name, "-n", ns })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
