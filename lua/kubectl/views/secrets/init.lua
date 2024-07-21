local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.secrets.definition")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("secrets")
    :setCmd({ "{{BASE}}/api/v1/{{NAMESPACE}}secrets?pretty=false" }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

      vim.schedule(function()
        self
          :addHints({
            { key = "<gd>", desc = "describe" },
          }, true, true, true)
          :display("k8s_secrets", "Secrets", cancellationToken)
      end)
    end)
end

function M.Edit(name, namespace)
  buffers.floating_buffer({}, {}, "k8s_secret_edit", { title = name, syntax = "yaml" })
  commands.execute_terminal("kubectl", { "edit", "secrets/" .. name, "-n", namespace })
end

function M.SecretDesc(namespace, name)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_secret_desc", name, "yaml")
    :setCmd({ "describe", "secret", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_secret_desc", name, "yaml")
end

return M
