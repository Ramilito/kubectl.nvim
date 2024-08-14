local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.configmaps.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new(definition.resource)
    :display(definition.ft, definition.display_name, cancellationToken)
    :setCmd(definition.url, "curl")
    :fetchAsync(function(self)
      self:decodeJson()

      vim.schedule(function()
        self
          :process(definition.processRow)
          :sort()
          :prettyPrint(definition.getHeaders)
          :addHints(definition.hints, true, true, true)
          :setContent(cancellationToken)
      end)
    end)
end

--- Edit a configmap
---@param name string
---@param namespace string
function M.Edit(name, namespace)
  buffers.floating_buffer("k8s_configmap_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "configmaps/" .. name, "-n", namespace })
end

--- Describe a configmap
---@param name string
---@param ns string
function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_configmaps_desc", name, "yaml")
    :setCmd({ "describe", "configmaps", name, "-n", ns })
    :fetch()
    :splitData()
    :setContentRaw()
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
