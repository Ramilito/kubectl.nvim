local M = {}

function M.get_items()
  local items = {}
  local seen = {}

  -- Lazy init: trigger cache initialization on first completion request
  require("kubectl").init_cache()

  -- Add viewsTable items first (higher priority)
  local viewsTable = require("kubectl.utils.viewsTable")
  for view_name, aliases in pairs(viewsTable) do
    for _, alias in ipairs(aliases) do
      if not seen[alias] then
        seen[alias] = true
        if alias == view_name then
          table.insert(items, {
            label = alias,
            labelDetails = { description = "view" },
            kind_name = "View",
            kind_icon = "󱃾",
          })
        else
          table.insert(items, {
            label = alias,
            labelDetails = { description = view_name },
            insertText = view_name,
          })
        end
      end
    end
  end

  -- Add cached API resources (skip if already seen)
  local cache_ok, cache = pcall(require, "kubectl.cache")
  if cache_ok and cache.cached_api_resources and cache.cached_api_resources.values then
    for name, resource in pairs(cache.cached_api_resources.values) do
      if type(name) == "string" and type(resource) == "table" then
        local scope = resource.namespaced and "namespaced" or "cluster-scoped"
        local kind_name = (resource.gvk and resource.gvk.k) or name
        if not seen[name] then
          seen[name] = true
          table.insert(items, {
            label = name,
            labelDetails = { description = kind_name },
            documentation = scope,
            kind_name = "Kind",
            kind_icon = "󱃾",
          })
        end
        if resource.short_names then
          for _, short in ipairs(resource.short_names) do
            if type(short) == "string" and not seen[short] then
              seen[short] = true
              table.insert(items, {
                label = short,
                labelDetails = { description = kind_name },
                insertText = name,
                kind_name = "Kind",
                kind_icon = "󱃾",
              })
            end
          end
        end
      end
    end
  end

  return items
end

function M.register()
  require("kubectl.completion.lsp").register_source("k8s_aliases", M.get_items)
end

return M
