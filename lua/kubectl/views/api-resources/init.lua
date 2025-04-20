local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local definition = require("kubectl.views.api-resources.definition")
local manager = require("kubectl.resource_manager")
local tables = require("kubectl.utils.tables")

local resource = "api-resources"

local M = {
  definition = {
    resource = resource,
    display_name = "API Resources",
    ft = "k8s_" .. resource,
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "show resource" },
    },
    headers = {
      "NAME",
      "SHORTNAMES",
      "APIVERSION",
      "NAMESPACED",
      "KIND",
    },
    processRow = definition.processRow,
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.buf_nr, builder.win_nr = buffers.buffer(M.definition.ft, builder.resource)
  builder.definition = M.definition
  M.Draw(cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    local cached_resources = cache.cached_api_resources
    builder.data = cached_resources.values
    builder.decodeJson()
    builder.process(definition.processRow, true)

    local windows = buffers.get_windows_by_name(M.definition.resource)
    for _, win_id in ipairs(windows) do
      builder.prettyPrint(win_id).addDivider(true).addHints(M.definition.hints, true, true)
      builder.displayContent(win_id, cancellationToken)
    end
  end
end

function M.Desc(_, _, _)
	return nil
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
