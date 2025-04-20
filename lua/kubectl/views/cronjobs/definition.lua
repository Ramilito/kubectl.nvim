local M = {}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")
local function getActive(row)
  local active = row and row.status and row.status.active
  if active == nil then
    return 0
  end
  return #active
end

local function getSelector(row)
  local selector = {}
  if row.spec.selector == nil then
    return "<none>"
  end
  for key, value in pairs(row.spec.selector.matchLabels) do
    table.insert(selector, key .. "=" .. value)
  end
  return table.concat(selector, ",")
end

local function getContainerData(row, key)
  local containers = {}
  if
    not row.spec
    or not row.spec.jobTemplate
    or not row.spec.jobTemplate.spec.template
    or not row.spec.jobTemplate.spec.template.spec
    or not row.spec.jobTemplate.spec.template.spec.containers
  then
    return ""
  end
  for _, container in ipairs(row.spec.jobTemplate.spec.template.spec.containers) do
    table.insert(containers, container[key])
  end
  return table.concat(containers, ",")
end

function M.processRow(rows)
  local data = {}

  if not rows then
    return data
  end

  if rows then
    for _, row in pairs(rows) do
      local cronjob = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        schedule = row.spec.schedule,
        suspend = { symbol = row.spec.suspend and hl.symbols.error or hl.symbols.success, value = row.spec.suspend },
        active = getActive(row),
        ["last schedule"] = time.since(row.status.lastScheduleTime, true) or "",
        containers = getContainerData(row, "name"),
        images = getContainerData(row, "image"),
        selector = getSelector(row),
        age = time.since(row.metadata.creationTimestamp, true),
      }

      table.insert(data, cronjob)
    end
  end
  return data
end

return M
