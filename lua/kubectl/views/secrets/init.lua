local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.secrets.definition")

local M = {}

function M.Secrets()
  ResourceBuilder:new("secrets", { "get", "secrets", "-A", "-o=json" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort(SORTBY):prettyPrint(definition.getHeaders):setFilter(FILTER)

    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true)
        :display("k8s_secrets", "Secrets")
    end)
  end)
end

function M.SecretDesc(namespace, name)
  ResourceBuilder:new("desc", { "describe", "secret", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_secret_desc", name, "yaml")
end

return M
