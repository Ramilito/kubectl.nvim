local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.secrets.definition")

local M = {}

function M.Secrets(cancellationToken)
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
  buffers.floating_buffer({}, {}, "yaml", {})
  local cmd = "kubectl edit secrets/" .. name .. " -n " .. namespace
  vim.fn.termopen(cmd)
end

function M.SecretDesc(namespace, name)
  ResourceBuilder:new("desc")
    :setCmd({ "describe", "secret", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_secret_desc", name, "yaml")
end

return M
