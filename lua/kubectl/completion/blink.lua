local M = {}

function M.new(opts)
  return setmetatable({ opts = opts or {} }, { __index = M })
end

function M:enabled()
  local ok, cache = pcall(require, "kubectl.cache")
  return ok and cache.cached_api_resources ~= nil
end

function M:get_completions(_ctx, callback)
  local cache = require("kubectl.cache")
  local items = {}

  for name, resource in pairs(cache.cached_api_resources.values or {}) do
    table.insert(items, {
      label = name,
      kind = vim.lsp.protocol.CompletionItemKind.Class,
      detail = resource.gvk and resource.gvk.k or nil,
      documentation = resource.namespaced and "namespaced" or "cluster-scoped",
    })
    for _, short in ipairs(resource.short_names or {}) do
      table.insert(items, {
        label = short,
        kind = vim.lsp.protocol.CompletionItemKind.Class,
        detail = name,
        insertText = name,
      })
    end
  end

  local ns_ok, ns_view = pcall(require, "kubectl.views.namespace")
  if ns_ok and ns_view.namespaces then
    for _, ns in ipairs(ns_view.namespaces) do
      table.insert(items, {
        label = ns,
        kind = vim.lsp.protocol.CompletionItemKind.Module,
        detail = "namespace",
      })
    end
  end

  local ctx_ok, ctx_view = pcall(require, "kubectl.resources.contexts")
  if ctx_ok and ctx_view.contexts then
    for _, context in ipairs(ctx_view.contexts) do
      table.insert(items, {
        label = context,
        kind = vim.lsp.protocol.CompletionItemKind.Variable,
        detail = "context",
      })
    end
  end

  callback({ items = items, is_incomplete_backward = false })
end

return M
