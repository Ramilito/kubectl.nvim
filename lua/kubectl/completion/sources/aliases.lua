local M = {}

function M.get_items()
  local items = {}

  -- Lazy init: trigger cache initialization on first completion request
  require("kubectl").init_cache()

  local cache_ok, cache = pcall(require, "kubectl.cache")
  if cache_ok and cache.cached_api_resources and cache.cached_api_resources.values then
    for name, resource in pairs(cache.cached_api_resources.values) do
      if type(name) == "string" and type(resource) == "table" then
        local scope = resource.namespaced and "namespaced" or "cluster-scoped"
        local kind_name = (resource.gvk and resource.gvk.k) or name
        table.insert(items, {
          label = name,
          labelDetails = { description = kind_name },
          documentation = scope,
          kind_name = "Kind",
          kind_icon = "󱃾",
        })
        if resource.short_names then
          for _, short in ipairs(resource.short_names) do
            if type(short) == "string" then
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

  local ns_ok, ns_view = pcall(require, "kubectl.views.namespace")
  if ns_ok and ns_view.namespaces then
    for _, ns in ipairs(ns_view.namespaces) do
      if type(ns) == "string" then
        table.insert(items, {
          label = ns,
          kind_name = "Namespace",
          kind_icon = "󱃾",
        })
      end
    end
  end

  local ctx_ok, ctx_view = pcall(require, "kubectl.resources.contexts")
  if ctx_ok and ctx_view.contexts then
    for _, context in ipairs(ctx_view.contexts) do
      if type(context) == "string" then
        table.insert(items, {
          label = context,
          kind_name = "Cluster",
          kind_icon = "󱃾",
        })
      end
    end
  end

  return items
end

function M.register()
  require("kubectl.completion.lsp").register_source("k8s_aliases", M.get_items)
end

return M
