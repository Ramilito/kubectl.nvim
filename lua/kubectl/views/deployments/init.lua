local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.deployments.definition")

local M = {}

function M.Deployments(cancellationToken)
  ResourceBuilder:new("deployments", "get --raw /apis/apps/v1/{{NAMESPACE}}deployments"):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders):setFilter()
    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "desc" },
          { key = "<enter>", desc = "pods" },
        }, true, true)
        :display("k8s_deployments", "Deployments", cancellationToken)
    end)
  end)
end

function M.DeploymentDesc(deployment_desc, namespace)
  ResourceBuilder:new("desc", { "describe", "deployment", deployment_desc, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_deployment_desc", deployment_desc, "yaml")
end

return M
