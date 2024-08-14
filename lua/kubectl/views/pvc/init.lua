local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pvc.definition")
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
          :setContent()
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_pvc_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "pvc/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_pvc_desc", name, "yaml")
    :setCmd({ "describe", "pvc", name, "-n", ns })
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
