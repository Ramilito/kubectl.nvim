local M = {
  resource = "jobs",
  display_name = "jobs",
  ft = "k8s_jobs",
  url = { "{{BASE}}/apis/batch/v1/{{NAMESPACE}}jobs?pretty=false" },
  hints = {
    { key = "<grr>", desc = "restart", long_desc = "Create job from job" },
    { key = "<gd>", desc = "desc", long_desc = "Describe selected job" },
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
      local job = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        completions = M.getCompletions(row),
        duration = M.getDuration(row),
        containers = M.getContainerData(row, "name"),
        images = M.getContainerData(row, "image"),
        selector = M.getSelector(row),
        age = time.since(row.metadata.creationTimestamp, true),
      }

      table.insert(data, job)
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "COMPLETIONS",
    "DURATION",
    "AGE",
    "CONTAINERS",
    "IMAGES",
    "SELECTOR",
  }

  return headers
end

function M.getDuration(row)
  local is_complete = row.status.completionTime
  local duration
  if is_complete then
    duration = time.since(row.metadata.creationTimestamp, false, vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", is_complete))
  else
    duration = time.since(row.metadata.creationTimestamp, false)
  end
  return duration
end

function M.getSelector(row)
  local selector = {}
  for key, value in pairs(row.spec.selector.matchLabels) do
    table.insert(selector, key .. "=" .. value)
  end
  return table.concat(selector, ",")
end

function M.getCompletions(row)
  local completions = { symbol = "", value = "" }
  local desired = row.spec.completions
  local actual = row.status.succeeded or 0
  if desired == actual then
    completions.symbol = hl.symbols.note
  else
    completions.symbol = hl.symbols.deprecated
  end
  completions.value = actual .. "/" .. desired
  return completions
end

function M.getContainerData(row, key)
  local containers = {}
  for _, container in ipairs(row.spec.template.spec.containers) do
    table.insert(containers, container[key])
  end
  return table.concat(containers, ",")
end

return M
