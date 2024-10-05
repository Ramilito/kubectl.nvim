local definition = require("kubectl.views.lineage.definition")
local logger = require("kubectl.utils.logging")
local view = require("kubectl.views")

local M = {}

function M.View(name, ns, kind)
  local data = definition.collect_all_resources(view.cached_api_resources.values)
  local graph = definition.build_graph(data)

  local selected_key = string.lower(kind) .. "/" .. ns .. "/" .. name

  local associated_resources = definition.find_associated_resources(graph, selected_key)
  logger.notify_table(associated_resources)

end

return M
