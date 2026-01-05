local M = {}

function M.get_items()
  local items = {}
  local state = require("kubectl.state")

  for _, entry in ipairs(state.filter_history) do
    table.insert(items, {
      label = entry,
      kind_name = "History",
      kind_icon = "󰋚",
    })
  end

  return items
end

function M.register()
  require("kubectl.completion.lsp").register_source("k8s_filter", M.get_items)
end

return M
