local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.secrets.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("secrets")
    :display("k8s_secrets", "Secrets", cancellationToken)
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}secrets?pretty=false" }, "curl")
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

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_secret_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "secrets/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_secret_desc", name, "yaml")
    :setCmd({ "get", "secret", name, "-n", ns, "-o", "yaml" })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self
          :addHints({
            { key = "<cr>", desc = "base64decode" },
          }, false, false, false)
          :setContentRaw()
      end)
    end)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
