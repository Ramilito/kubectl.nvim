local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.nodes.definition")

local M = {}

function M.Nodes(cancellationToken)
  ResourceBuilder:new("nodes"):setCmd({ "get", "--raw", "/api/v1/nodes" }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders):setFilter()
    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true)
        :display("k8s_nodes", "Nodes", cancellationToken)
    end)
  end)
end

function M.NodeDesc(node)
  ResourceBuilder:new("desc"):setCmd({ "describe", "node", node }):fetchAsync(function(self)
    self:splitData()
    vim.schedule(function()
      self:displayFloat("k8s_node_desc", "node_desc", "yaml")
    end)
  end)
end

return M
