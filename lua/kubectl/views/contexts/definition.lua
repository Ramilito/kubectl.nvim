local M = {
  resource = "contexts",
  display_name = "contexts",
  ft = "k8s_contexts",
  url = { "config", "view", "-ojson" },
}

function M.processRow(rows)
  local data = {}
  local servers = {}
  for _, cluster in ipairs(rows.clusters) do
    servers[cluster.name] = cluster.cluster.server
  end
  -- rows.contexts
  for _, row in ipairs(rows.contexts) do
    local context = {
      name = row.name,
      server = servers[row.context.cluster],
      user = row.context.user,
      namespace = row.context.namespace,
    }

    table.insert(data, context)
  end

  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "SERVER",
    "USER",
    "NAMESPACE",
  }

  return headers
end

return M
