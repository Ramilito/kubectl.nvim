local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")
local definition = require("kubectl.views.deployments.definition")

local M = {}

function M.Deployments(cancellationToken)
  ResourceBuilder:new("deployments"):setCmd({ "get", "--raw", "/apis/apps/v1/{{NAMESPACE}}deployments" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
    vim.schedule(function()
      self
        :addHints({
          { key = "<r>", desc = "restart" },
          { key = "<d>", desc = "desc" },
          { key = "<enter>", desc = "pods" },
        }, true, true)
        :display("k8s_deployments", "Deployments", cancellationToken)
    end)
  end)
end

function M.Edit(name, namespace)
  actions.floating_buffer({}, {}, "yaml", {})

  local cmd = "kubectl edit deployments/" .. name .. " -n " .. namespace
  vim.fn.termopen(cmd)
end

function M.DeploymentDesc(deployment_desc, namespace)
  ResourceBuilder:new("desc"):setCmd({ "describe", "deployment", deployment_desc, "-n", namespace }):fetchAsync(function(self)
    self:splitData()
    vim.schedule(function()
      self:displayFloat("k8s_deployment_desc", deployment_desc, "yaml")
    end)
  end)
end

return M
