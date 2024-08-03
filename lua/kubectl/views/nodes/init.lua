local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.nodes.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:new("nodes"):setCmd({ "{{BASE}}/api/v1/nodes?pretty=false" }, "curl"):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
    vim.schedule(function()
      self
        :addHints({
          { key = "<gd>", desc = "describe" },
          { key = "<gC>", desc = "cordon" },
          { key = "<gU>", desc = "uncordon" },
          { key = "<gR>", desc = "drain" },
        }, true, true, true)
        :display("k8s_nodes", "Nodes", cancellationToken)
    end)
  end)
end

function M.Drain(node)
  commands.shell_command_async("kubectl", { "drain", "nodes/" .. node })
end

function M.UnCordon(node)
  commands.shell_command_async("kubectl", { "uncordon", "nodes/" .. node })
end

function M.Cordon(node)
  commands.shell_command_async("kubectl", { "cordon", "nodes/" .. node })
end

function M.Desc(node)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_node_desc", "node_desc", "yaml")
    :setCmd({ "describe", "node", node })
    :fetchAsync(function(self)
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

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
