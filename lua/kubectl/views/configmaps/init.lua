local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.configmaps.definition")

local M = {}

function M.Configmaps(cancellationToken)
  ResourceBuilder:new("configmaps", { "get", "--raw", "/api/v1/{{NAMESPACE}}configmaps" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders):setFilter()

    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true)
        :display("k8s_configmaps", "Configmaps", cancellationToken)
    end)
  end)
end

function M.ConfigmapsDesc(namespace, name)
  ResourceBuilder:new("desc", { "describe", "configmaps", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_configmaps_desc", name, "yaml")
end

return M
