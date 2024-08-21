local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")
local root_definition = require("kubectl.views.definition")
local tables = require("kubectl.utils.tables")

local M = { builder = nil, pfs = {} }

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true, "svc")
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken)
  end
end

function M.Draw(cancellationToken)
  M.builder = M.builder:draw(definition, cancellationToken)
  root_definition.setPortForwards(M.builder.extmarks, M.builder.prettyData, M.pfs)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_service_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "services/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_svc_desc", name, "yaml")
    :setCmd({ "describe", "svc", name, "-n", ns })
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
  return tables.getCurrentSelection(2, 1)
end

return M
