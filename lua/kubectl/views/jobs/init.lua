local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.jobs.definition")
local find = require("kubectl.utils.find")
local tables = require("kubectl.utils.tables")

local M = {
  builder = nil,
  owner = { name = nil, ns = nil },
}

function M.View(cancellationToken)
  if M.builder then
    M.builder = M.builder:view(definition, cancellationToken)
  else
    M.builder = ResourceBuilder:new(definition.resource):view(definition, cancellationToken, { cmd = "curl" })
  end
end

function M.Draw(cancellationToken)
  if M.owner.name and M.owner.ns then
    local filtered_data = find.filter(M.builder.data.items, function(item)
      local metadata = item.metadata
      local owner_references = metadata.ownerReferences

      return metadata.namespace == M.owner.ns and owner_references and owner_references[1].name == M.owner.name
    end)
    M.builder.data = { items = filtered_data }
  end

  M.builder = M.builder:draw(definition, cancellationToken)
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_job_desc", name, "yaml")
    :setCmd({ "describe", "job", name, "-n", ns })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:setContentRaw()
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_job_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "jobs/" .. name, "-n", ns })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
