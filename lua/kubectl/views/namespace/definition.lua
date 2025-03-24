local config = require("kubectl.config")
local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local M = {
  resource = "namespace",
  display_name = "Namespace",
  ft = "k8s_namespace",
  url = { "{{BASE}}/api/v1/namespaces?pretty=false" },
}

function M.processRow(rows)
  local data = {}
  table.insert(data, { name = "All", status = "", age = "" })

  if config.options.namespace_fallback then
    for _, value in ipairs(config.options.namespace_fallback) do
      table.insert(data, {
        name = { value = value, symbol = hl.symbols.success },
        status = { value = "<- config", symbol = hl.symbols.pending },
        age = "",
      })
    end
  end

  if rows.code == 401 or rows.code == 403 then
    table.insert(data, {
      name = {
        value = "⚠️ Access to namespaces denied, please input your desired namespace",
        symbol = hl.symbols.warning,
      },
      status = "",
      age = "",
    })
    return data
  end

  if not rows then
    return data
  end

  for _, row in pairs(rows) do
    local ns = {
      name = { value = row.metadata.name, symbol = hl.symbols.success },
      status = { symbol = events.ColorStatus(row.status.phase), value = row.status.phase },
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, ns)
  end

  return data
end

return M
