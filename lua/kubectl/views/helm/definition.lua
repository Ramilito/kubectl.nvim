local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {
  resource = "helm",
  display_name = "Helm",
  ft = "k8s_helm",
  cmd = "helm",
  url = { "ls", "-a", "-A", "--output", "json" },
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "show resource" },
  },
}

function M.processRow(rows)
  if not rows then
    return data
  end
  local data = {}
  for _, row in ipairs(rows) do
    local helm = {
      namespace = row.namespace,
      name = row.name,
      revision = row.revision,
      status = { symbol = events.ColorStatus(row.status), value = row.status },
      chart = row.chart,
      ["app-version"] = row["app_version"],
    }
    local updated = string.gsub(row.updated, "%..*", "")
    helm.updated = time.since(updated, nil, nil, "%Y-%m-%d %H:%M:%S")
    table.insert(data, helm)
  end
  return data
end

function M.getHeaders()
  return {
    "NAMESPACE",
    "NAME",
    "REVISION",
    "UPDATED",
    "STATUS",
    "CHART",
    "APP-VERSION",
  }
end

return M
