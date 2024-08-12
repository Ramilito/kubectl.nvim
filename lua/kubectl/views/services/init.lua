local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")
local root_definition = require("kubectl.views.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  local pfs = {}
  root_definition.getPFData(pfs, true, "svc")
  ResourceBuilder:new(definition.resource)
    :display(definition.ft, definition.display_name, cancellationToken)
    :setCmd(definition.url, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
      vim.schedule(function()
        root_definition.setPortForwards(self.extmarks, self.prettyData, pfs)
        self:addHints(definition.hints, true, true, true):setContent()
      end)
    end)
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
