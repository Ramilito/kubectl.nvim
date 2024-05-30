local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local secrets = require("kubectl.views.secrets")

local M = {}

function M.Secrets()
  ResourceBuilder:new("secrets", { "get", "secrets", "-A", "-o=json" })
    :fetch()
    :decodeJson()
    :process(secrets.processRow)
    :prettyPrint(secrets.getHeaders)
    :addHints({
      { key = "<d>", desc = "describe" },
    }, true, true)
    :setFilter(FILTER)
    :display("k8s_secrets", "Secrets")
end

function M.SecretDesc(namespace, name)
  ResourceBuilder:new("desc", { "describe", "secret", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_secret_desc", name, "yaml")
end

return M
