local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local M = {
  resource = "namespace",
  display_name = "Namespace",
  ft = "k8s_namespace",
  url = { "{{BASE}}/api/v1/namespaces?pretty=false" },
}

function M.processLimitedRow(rows)
  local data = M.processRow(rows)
  table.remove(data, 1)

  return data
end
function M.processRow(rows)
  local data = {}

  if rows.code == 401 or rows.code == 403 then
    table.insert(data, {
      name = { value = "Access to namespaces denied, please input your desired namespace", symbol = hl.symbols.error },
      status = "",
      age = "",
    })
    return data
  end

  data = { { name = "All", status = "", age = "" } }
  if not rows.items then
    return data
  end

  for _, row in pairs(rows.items) do
    local ns = {
      name = row.metadata.name,
      status = { symbol = events.ColorStatus(row.status.phase), value = row.status.phase },
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, ns)
  end

  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "STATUS",
    "AGE",
  }

  return headers
end

return M
