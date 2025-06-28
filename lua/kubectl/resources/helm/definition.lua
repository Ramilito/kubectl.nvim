local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {}

function M.processRow(rows)
  local data = {}
  if not rows then
    return data
  end
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

return M
