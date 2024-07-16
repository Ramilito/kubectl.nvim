local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.nodes.definition")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("nodes"):setCmd({ "{{BASE}}/api/v1/nodes?pretty=false" }, "curl"):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
    vim.schedule(function()
      self
        :addHints({
          { key = "<d>", desc = "describe" },
        }, true, true, true)
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

function M.Edit(_, name)
  buffers.floating_buffer({}, {}, "k8s_node_edit", { title = name, syntax = "yaml" })
  commands.execute_terminal("kubectl", { "edit", "nodes/" .. name })
end

return M
