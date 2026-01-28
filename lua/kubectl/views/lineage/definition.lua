local M = {}

M.resource = "lineage"
M.display_name = "Lineage"
M.ft = "k8s_lineage"
M.title = "Lineage"

M.hints = {
  { key = "<Plug>(kubectl.select)", desc = "go to" },
  { key = "<Plug>(kubectl.refresh)", desc = "refresh cache" },
  { key = "<Plug>(kubectl.toggle_orphan_filter)", desc = "toggle orphans" },
  { key = "<Plug>(kubectl.impact_analysis)", desc = "impact analysis" },
  { key = "<Plug>(kubectl.export_dot)", desc = "export DOT" },
  { key = "<Plug>(kubectl.export_mermaid)", desc = "export Mermaid" },
}

M.panes = {
  { title = "Lineage" },
}

--- Reverse lookup: Kind → resource name using cache
--- @param kind string The Kind like "Pod", "Deployment"
--- @return string|nil The resource name like "pods", "deployments"
function M.find_resource_name(kind)
  local cache = require("kubectl.cache")
  local kind_lower = string.lower(kind)

  for resource_name, resource_info in pairs(cache.cached_api_resources.values) do
    if resource_info.gvk and resource_info.gvk.k then
      if string.lower(resource_info.gvk.k) == kind_lower then
        return resource_name
      end
    end
  end

  return nil
end

return M
