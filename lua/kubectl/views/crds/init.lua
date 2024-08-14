local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.crds.definition")
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
function M.Edit(name)
  buffers.floating_buffer("k8s_crds_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "crds/" .. name })
end

--- Describe a configmap
---@param name string
function M.Desc(name)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_crds_desc", name, "yaml")
    :setCmd({ "describe", "crds", name })
    :fetch()
    :splitData()
    :setContentRaw()
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
