local M = {}

function M.get_items()
  local items = {}

  local ns_ok, ns_view = pcall(require, "kubectl.views.namespace")
  if ns_ok and ns_view.namespaces then
    for _, ns in ipairs(ns_view.namespaces) do
      if type(ns) == "string" then
        table.insert(items, {
          label = ns,
          kind_name = "Namespace",
          kind_icon = "󰘧",
        })
      end
    end
  end

  return items
end

function M.register()
  require("kubectl.completion.lsp").register_source("k8s_namespaces", M.get_items)
end

return M
