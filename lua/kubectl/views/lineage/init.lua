local ResourceBuilder = require("kubectl.resourcebuilder")
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

  local builder = ResourceBuilder:new(definition.resource)
  builder:displayFloatFit(definition.ft, definition.resource, definition.syntax)

  builder.data = { "Associated Resources: " }
  for _, res in ipairs(associated_resources) do
    table.insert(builder.data, string.rep("    ", res.level) .. "- " .. res.kind .. ": " .. res.ns .. "/" .. res.name)
  end

  builder:splitData()
  builder:setContentRaw()
end

return M
