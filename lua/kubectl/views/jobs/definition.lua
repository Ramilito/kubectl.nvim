local M = {
  resource = "jobs",
  display_name = "Jobs",
  ft = "k8s_jobs",
  url = { "{{BASE}}/apis/batch/v1/{{NAMESPACE}}jobs?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
  },
  owner = { name = nil, ns = nil },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function getDuration(row)
  local is_complete = row and row.status and row.status.completionTime
  local duration
  if is_complete then
    duration = time.since(row.metadata.creationTimestamp, false, vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", is_complete))
  else
    duration = time.since(row.metadata.creationTimestamp, false)
  end
  return duration
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

local function getCompletions(row)
  local completions = { symbol = "", value = "" }
  local desired = row and row.spec and row.spec.completions or "0"
  local actual = row and row.status and row.status.succeeded or "0"
  if desired == actual then
    completions.symbol = hl.symbols.note
  else
    completions.symbol = hl.symbols.deprecated
  end
  completions.value = actual .. "/" .. desired
  return completions
end

local function getContainerData(row, key)
  if
    not row
    or not row.spec
    or not row.spec.template
    or not row.spec.template.spec
    or not row.spec.template.spec.containers
  then
    return ""
  end
  local containers = {}
  for _, container in ipairs(row.spec.template.spec.containers) do
    table.insert(containers, container[key])
  end
  return table.concat(containers, ",")
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  if rows and rows.items then
    for _, row in ipairs(rows.items) do
      local job = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        completions = getCompletions(row),
        duration = getDuration(row),
        containers = getContainerData(row, "name"),
        images = getContainerData(row, "image"),
        selector = getSelector(row),
        age = time.since(row.metadata.creationTimestamp, true),
      }

      local isOwnerMatching = M.owner.name
        and M.owner.ns
        and row.metadata.ownerReferences
        and row.metadata.namespace == M.owner.ns
        and row.metadata.ownerReferences[1].name == M.owner.name

      if isOwnerMatching or not (M.owner.name and M.owner.ns) then
        table.insert(data, job)
      end
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

return M
