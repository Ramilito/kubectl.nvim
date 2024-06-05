local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.services.definition")

local M = {}

function M.Services()
  ResourceBuilder:new("services", { "get", "services", "-A", "-o=json" }):fetchAsync(function(self)
    self
      :decodeJson()
      :process(definition.processRow)
      :sort(SORTBY)
      :prettyPrint(definition.getHeaders)
      :addHints({
        { key = "<d>", desc = "describe" },
      }, true, true)
      :setFilter(FILTER)

    vim.schedule(function()
      self:display("k8s_services", "Services")
    end)
  end)
end

function M.ServiceDesc(namespace, name)
  ResourceBuilder:new("desc", { "describe", "svc", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_svc_desc", name, "yaml")
end

return M
