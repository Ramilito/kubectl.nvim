local ResourceBuilder = require("kubectl.resourcebuilder")
local services = require("kubectl.views.services")

local M = {}

function M.Services()
  ResourceBuilder:new("services", { "get", "services", "-A", "-o=json" })
    :fetch()
    :decodeJson()
    :process(services.processRow)
    :prettyPrint(services.getHeaders)
    :addHints({
      { key = "<d>", desc = "describe" },
    }, true, true)
    :setFilter(FILTER)
    :display("k8s_services", "Services")
end

function M.ServiceDesc(namespace, name)
  ResourceBuilder:new("desc", { "describe", "svc", name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_svc_desc", name, "yaml")
end

return M
