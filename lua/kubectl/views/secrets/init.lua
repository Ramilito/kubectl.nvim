local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.secrets.definition")
local commands   = require("kubectl.actions.commands")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("secrets"):setCmd({ "get", "--raw", "/api/v1/{{NAMESPACE}}secrets" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true)
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
    :setCmd({ "describe", "secret", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_secret_desc", name, "yaml")
end

return M
