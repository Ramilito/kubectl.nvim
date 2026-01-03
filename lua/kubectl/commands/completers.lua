local M = {}

--- Complete namespace names
---@return string[]
function M.namespaces()
  local ok, ns_view = pcall(require, "kubectl.views.namespace")
  if ok then
    return ns_view.listNamespaces()
  end
  return {}
end

--- Complete output format options
---@return string[]
function M.output_formats()
  return { "json", "yaml", "wide", "name", "custom-columns", "jsonpath", "go-template" }
end

--- Complete resource type names
---@return string[]
function M.resources()
  local ok, cache = pcall(require, "kubectl.cache")
  if not ok or not cache.cached_api_resources then
    return {}
  end

  local names = {}
  for _, res in pairs(cache.cached_api_resources.values or {}) do
    if res.name then
      table.insert(names, res.name)
    end
  end
  return names
end

--- Complete label selector syntax
---@return string[]
function M.label_selectors()
  return { "app=", "environment=", "tier=", "version=" }
end

--- Complete field selector syntax
---@return string[]
function M.field_selectors()
  return { "metadata.name=", "metadata.namespace=", "status.phase=" }
end

--- Common flags shared across many commands
---@type FlagSpec[]
M.common_flags = {
  { name = "namespace", short = "n", takes_value = true, complete = M.namespaces },
  { name = "output", short = "o", takes_value = true, complete = M.output_formats },
  { name = "all-namespaces", short = "A", takes_value = false },
  { name = "selector", short = "l", takes_value = true, complete = M.label_selectors },
  { name = "field-selector", takes_value = true, complete = M.field_selectors },
  { name = "context", takes_value = true },
  { name = "kubeconfig", takes_value = true },
}

--- Get flags with resource completion for a command
---@return FlagSpec[]
function M.get_flags()
  return vim.list_extend({}, M.common_flags)
end

return M
