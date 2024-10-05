local definition = require("kubectl.views.lineage.definition")
local logger = require("kubectl.utils.logging")
local view = require("kubectl.views")

local M = {}

function M.View(name, ns, kind)
  local data = definition.collect_all_resources(view.cached_api_resources.values)
  local graph = definition.build_graph(data)
  if kind:sub(-1) == "s" then
    kind = kind:sub(1, -2)
  end
  local selected_key = kind .. "/" .. ns .. "/" .. name

  local associated_resources = definition.find_associated_resources(graph, selected_key)

  print("Associated Resources:", selected_key)
  for _, res in ipairs(associated_resources) do
    local res_ns = res.ns or "cluster"
    print("- " .. res.kind .. ": " .. res_ns .. "/" .. res.name)
  end
end

return M
