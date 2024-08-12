local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.crds.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("crds")
    :display("k8s_crds", "CRDS", cancellationToken)
    :setCmd({ "{{BASE}}/apis/apiextensions.k8s.io/v1/customresourcedefinitions?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

      vim.schedule(function()
        self
          :addHints({
            { key = "<gd>", desc = "describe" },
          }, true, true, true)
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
