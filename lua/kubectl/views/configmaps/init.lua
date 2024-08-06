local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.configmaps.definition")
local tables = require("kubectl.utils.tables")

local M = {}

--- View configmaps using ResourceBuilder
---@param cancellationToken? boolean
function M.View(cancellationToken)
  ResourceBuilder:new("configmaps")
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}configmaps?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

      vim.schedule(function()
        self
          :addHints({
            { key = "<gd>", desc = "describe" },
          }, true, true, true)
          :display("k8s_configmaps", "Configmaps", cancellationToken)
      end)
    end)
end

--- Edit a configmap
---@param name string
---@param namespace string
function M.Edit(name, namespace)
  buffers.floating_buffer({}, {}, "k8s_configmap_edit", { title = name, syntax = "yaml" })
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
    :displayFloat("k8s_configmaps_desc", name, "yaml")
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
