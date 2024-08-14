local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.daemonsets.definition")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  ResourceBuilder:main_view(definition, cancellationToken)
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_daemonset_desc", name, "yaml")
    :setCmd({ "describe", "daemonset", name, "-n", ns })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:setContentRaw()
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_daemonset_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "daemonsets/" .. name, "-n", ns })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
