local M = {}

function M.get_items()
  local items_map = {}

  -- Add cached API resources (populated when plugin opens)
  local cache_ok, cache = pcall(require, "kubectl.cache")
  if cache_ok and cache.cached_api_resources and cache.cached_api_resources.values then
    for name, resource in pairs(cache.cached_api_resources.values) do
      if type(name) == "string" and type(resource) == "table" then
        local scope = resource.namespaced and "namespaced" or "cluster-scoped"
        local kind_name = (resource.gvk and resource.gvk.k) or name
        if not items_map[name] then
          items_map[name] = {
            label = name,
            labelDetails = { description = kind_name },
            documentation = scope,
            kind_name = "Kind",
            kind_icon = "󱃾",
          }
        end
        if resource.short_names then
          for _, short in ipairs(resource.short_names) do
            if type(short) == "string" and not items_map[short] then
              items_map[short] = {
                label = short,
                labelDetails = { description = kind_name },
                insertText = name,
                kind_name = "Kind",
                kind_icon = "󱃾",
              }
            end
          end
        end
      end
    end
  end

  -- Add custom views (plugin-specific, not Kubernetes resources)
  local custom_views = {
    "overview",
    "api-resources",
    "contexts",
    "top",
    "drift",
    "helm",
  }
  local viewsTable = require("kubectl.utils.viewsTable")
  for _, view_name in ipairs(custom_views) do
    local aliases = viewsTable[view_name]
    if aliases then
      for _, alias in ipairs(aliases) do
        items_map[alias] = {
          label = alias,
          labelDetails = { description = "view" },
          kind_name = "View",
          kind_icon = "󱃾",
        }
      end
    end
  end

  -- Convert map to list
  local items = {}
  for _, item in pairs(items_map) do
    table.insert(items, item)
  end

  return items
end

function M.register()
  require("kubectl.lsp").register_source("k8s_aliases", M.get_items)
end

return M
