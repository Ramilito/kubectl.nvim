local ResourceBuilder = require("kubectl.resourcebuilder")
-- local buffers = require("kubectl.actions.buffers")
-- local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.api-resources.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
  -- if #vim.tbl_keys(cached_resources.values) == 0 then
  --   return
  -- end

  local self = state.instance
  if not self or not self.resource or self.resource ~= definition.resource then
    self = ResourceBuilder:new(definition.resource)
  end

  self:display(definition.ft, definition.resource, cancellationToken)

  state.instance = self
  self.data = cached_resources and cached_resources.values or {}

  vim.schedule(function()
    M.Draw(cancellationToken)
  end)
end

function M.Draw(cancellationToken)
  if #state.instance.data == 0 then
    local cached_resources = require("kubectl.views").cached_api_resources
    if #vim.tbl_keys(cached_resources.values) > 0 then
      state.instance.data = cached_resources.values
    end
  end
  state.instance:draw(definition, cancellationToken)
end

-- function M.Desc(node, _, reload)
--   ResourceBuilder:view_float({
--     resource = "nodes_desc_" .. node,
--     ft = "k8s_node_desc",
--     url = { "describe", "node", node },
--     syntax = "yaml",
--   }, { cmd = "kubectl", reload = reload })
-- end

-- function M.Edit(_, name)
--   buffers.floating_buffer("k8s_node_edit", name, "yaml")
--   commands.execute_terminal("kubectl", { "edit", "nodes/" .. name })
-- end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
