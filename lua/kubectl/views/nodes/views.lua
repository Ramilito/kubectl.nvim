local nodes = require("kubectl.views.nodes")
local ResourceBuilder = require("kubectl.resourcebuilder")

local M = {}

function M.Nodes()
  ResourceBuilder:new("nodes", { "get", "nodes", "-A", "-o=json" })
    :fetch()
    :decodeJson()
    :process(nodes.processRow)
    :prettyPrint(nodes.getHeaders)
    :addHints({
      { key = "<d>", desc = "describe" },
    }, true, true)
    :display("k8s_nodes", "Nodes")
end

function M.NodeDesc(node)
  ResourceBuilder:new("desc", { "describe", "node", node })
    :fetch()
    :splitData()
    :displayFloat("k8s_node_desc", "node_desc", "yaml")
end

return M
