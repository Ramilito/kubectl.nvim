local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.nodes.definition")

local M = {}

function M.Nodes()
  ResourceBuilder:new("nodes", { "get", "nodes", "-A", "-o=json" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort(SORTBY):prettyPrint(definition.getHeaders):addHints({
      { key = "<d>", desc = "describe" },
    }, true, true)
    vim.schedule(function()
      self:display("k8s_nodes", "Nodes")
    end)
  end)
end

function M.NodeDesc(node)
  ResourceBuilder:new("desc", { "describe", "node", node })
    :fetch()
    :splitData()
    :displayFloat("k8s_node_desc", "node_desc", "yaml")
end

return M
