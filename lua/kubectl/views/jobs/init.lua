local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.jobs.definition")
local informer = require("kubectl.actions.informer")
local tables = require("kubectl.utils.tables")

local M = {
  builder = nil,
}

function M.View(cancellationToken, from_cronjob)
  if M.builder then
    M.builder = M.builder
        :display(definition.ft, definition.display_name, cancellationToken)
        :setCmd(definition.url, "curl")
        :fetchAsync(function(builder)
          builder:decodeJson()
          informer.start(builder)
          vim.schedule(function()
            M.Draw(cancellationToken, from_cronjob)
          end)
        end)
  else
    M.builder = ResourceBuilder:new(definition.resource)
        :display(definition.ft, definition.display_name, cancellationToken)
        :setCmd(definition.url, "curl")
        :fetchAsync(function(builder)
          builder:decodeJson()
          informer.start(builder)
          vim.schedule(function()
            M.Draw(cancellationToken, from_cronjob)
          end)
        end)
  end
end

function M.Draw(cancellationToken, from_cronjob)
  M.builder = M.builder
  local data = M.builder.data
  if from_cronjob then
    local filtered_data = {}
    for _, item in ipairs(data.items) do
      if item.metadata.namespace == from_cronjob.ns and item.metadata.ownerReferences and item.metadata.ownerReferences[1].name == from_cronjob.name then
        table.insert(filtered_data, item)
      end
    end
    M.builder.data = { items = filtered_data }
  end

  M.builder = M.builder
      :process(definition.processRow):sort():prettyPrint(definition.getHeaders)

  M.builder = M.builder:addHints(definition.hints, true, true, true):setContent(cancellationToken)
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
