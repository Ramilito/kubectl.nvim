local hl = require("kubectl.actions.highlight")
local M = {
  resource = "contexts",
  display_name = "contexts",
  ft = "k8s_contexts",
  url = { "config", "view", "-ojson" },
}

function M.processRow(rows)
  local data = {}
  -- rows.contexts
  for _, row in ipairs(rows.contexts) do
    local context = {
      name = { value = row.name, symbol = hl.symbols.success },
      namespace = row.context.namespace or "",
      cluster = row.context.cluster or "",
      user = row.context.user or "",
    }

    table.insert(data, context)
  end

  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "NAMESPACE",
    "CLUSTER",
    "USER",
  }

  return headers
end

return M
