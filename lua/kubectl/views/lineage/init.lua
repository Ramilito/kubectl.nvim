local ResourceBuilder = require("kubectl.resourcebuilder")
local cache = require("kubectl.utils.cache")
local definition = require("kubectl.views.lineage.definition")
local logger = require("kubectl.utils.logging")
local view = require("kubectl.views")

local M = {}

function M.View(name, ns, kind)
  local builder = ResourceBuilder:new(definition.resource)
  builder:displayFloatFit(definition.ft, definition.resource, definition.syntax)

  local hints = {
    { key = "<Plug>(kubectl.select)", desc = "go to" },
  }

  builder.data = { "Associated Resources: " }
  if cache.loading then
    table.insert(builder.data, "")
    table.insert(builder.data, "Cache still loading...")
  else
    local data = definition.collect_all_resources(view.cached_api_resources.values)
    local graph = definition.build_graph(data)
    -- TODO: Our views are in plural form, we remove the last s for that...not really that robust
    if kind:sub(-1) == "s" then
      kind = kind:sub(1, -2)
    end
    local selected_key = kind
    if ns then
      selected_key = selected_key .. "/" .. ns
    end
    selected_key = selected_key .. "/" .. name

    local associated_resources = definition.find_associated_resources(graph, selected_key)

    for _, res in ipairs(associated_resources) do
      table.insert(builder.data, string.rep("    ", res.level) .. "- " .. res.kind .. ": " .. (res.ns or "") .. "/" .. res.name)
    end
  end

  builder:splitData()
  builder:addHints(hints, false, false, false)
  builder:setContentRaw()
end

return M
