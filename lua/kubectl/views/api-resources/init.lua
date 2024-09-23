local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.api-resources.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

function M.View(cancellationToken)
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

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
