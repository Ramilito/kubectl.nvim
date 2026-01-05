local M = {}

function M.get_items()
  local items = {}

  local ctx_ok, ctx_view = pcall(require, "kubectl.resources.contexts")
  if ctx_ok and ctx_view.contexts then
    for _, context in ipairs(ctx_view.contexts) do
      if type(context) == "string" then
        table.insert(items, {
          label = context,
          kind_name = "Context",
          kind_icon = "󱃾",
        })
      end
    end
  end

  return items
end

function M.register()
  require("kubectl.completion.lsp").register_source("k8s_contexts", M.get_items)
end

return M
