local M = {
  resource = "cronjobs",
  display_name = "Cronjobs",
  ft = "k8s_cronjobs",
  url = { "{{BASE}}/apis/batch/v1/{{NAMESPACE}}cronjobs?pretty=false" },
  hints = {
    { key = "<grr>", desc = "restart", long_desc = "Create job from cronjob" },
    { key = "<gd>", desc = "desc", long_desc = "Describe selected cronjob" },
    { key = "<enter>", desc = "pods", long_desc = "Opens pods view" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local cronjob = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        schedule = row.spec.schedule,
        suspend = { symbol = row.spec.suspend and hl.symbols.error or hl.symbols.success, value = row.spec.suspend },
        active = M.getActive(row),
        ["last schedule"] = time.since(row.status.lastScheduleTime, true) or "",
        containers = M.getContainerData(row, "name"),
        images = M.getContainerData(row, "image"),
        selector = M.getSelector(row),
        age = time.since(row.metadata.creationTimestamp, true),
      }

      table.insert(data, cronjob)
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "SCHEDULE",
    "SUSPEND",
    "ACTIVE",
    "LAST SCHEDULE",
    "AGE",
    "CONTAINERS",
    "IMAGES",
    "SELECTOR",
  }

  return headers
end

function M.getActive(row)
  local active = row.status.active
  if active == nil then
    return 0
  end
  return #active
end

function M.getSelector(row)
  local selector = {}
  if row.spec.selector == nil then
    return "<none>"
  end
  for key, value in pairs(row.spec.selector.matchLabels) do
    table.insert(selector, key .. "=" .. value)
  end
  return table.concat(selector, ",")
end

function M.getContainerData(row, key)
  local containers = {}
  for _, container in ipairs(row.spec.jobTemplate.spec.template.spec.containers) do
    table.insert(containers, container[key])
  end
  return table.concat(containers, ",")
end

return M
