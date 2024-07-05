local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local definition = require("kubectl.views.services.definition")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("services"):setCmd({ "get", "--raw", "/api/v1/{{NAMESPACE}}services" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)

    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true)
        -- TODO: Added space to title otherwise netrw is opening for some reason..
        :display(
          "k8s_services",
          "Services ",
          cancellationToken
        )
    end)
  end)
end

function M.Edit(name, namespace)
  buffers.floating_buffer({}, {}, "yaml", {})
  local cmd = "kubectl edit services/" .. name .. " -n " .. namespace
  vim.fn.termopen(cmd)
end

function M.ServiceDesc(namespace, name)
  ResourceBuilder:new("desc"):setCmd({ "describe", "svc", name, "-n", namespace }):fetchAsync(function(self)
    self:splitData()
    vim.schedule(function()
      self:displayFloat("k8s_svc_desc", name, "yaml")
    end)
  end)
end

return M
