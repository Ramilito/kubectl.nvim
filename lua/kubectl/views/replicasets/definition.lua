local M = {
  resource = "replicasets",
  display_name = "Replicasets",
  ft = "k8s_replicasets",
  url = { "{{BASE}}/apis/apps/v1/{{NAMESPACE}}replicasets?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.set_image)", desc = "set image", long_desc = "Change replicaset image" },
    { key = "<Plug>(kubectl.rollout_restart)", desc = "restart", long_desc = "Restart selected replicaset" },
    { key = "<Plug>(kubectl.scale)", desc = "scale", long_desc = "Scale replicas" },
    { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
  },
}
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")

local function verifyContainers(row)
  if
    not row
    or not row.spec
    or not row.spec.template
    or not row.spec.template.spec
    or not row.spec.template.spec.containers
  then
    return false
  end
  return true
end

local function getDesiredReplicas(row)
  if not row or not row.spec or not row.spec.replicas then
    return { value = 0, sort_by = 0 }
  end
  local desired = row.spec.replicas
  return { value = desired, sort_by = tonumber(desired) }
end

local function getColoredReplicas(row, replicas)
  local desired = getDesiredReplicas(row).sort_by
  local replicas_num = tonumber(replicas)
  local obj = { value = replicas, sort_by = replicas_num }
  if replicas_num < desired then
    obj.symbol = hl.symbols.deprecated
  else
    obj.symbol = hl.symbols.note
  end

  return obj
end

local function getCurrentReplicas(row)
  local current
  if not row or not row.status or not row.status.replicas then
    current = 0
  else
    current = row.status.replicas
  end
  return getColoredReplicas(row, current)
end

local function getReadyReplicas(row)
  local ready
  if not row or not row.status or not row.status.readyReplicas then
    ready = 0
  else
    ready = row.status.readyReplicas
  end
  return getColoredReplicas(row, ready)
end

local function getSelectors(row)
  if not row or not row.spec or not row.spec.selector or not row.spec.selector.matchLabels then
    return ""
  end
  local selectors = {}
  for key, value in pairs(row.spec.selector.matchLabels) do
    table.insert(selectors, key .. "=" .. value)
  end
  table.sort(selectors)
  return table.concat(selectors, ",")
end

local function getContainers(row)
  if not verifyContainers(row) then
    return ""
  end
  local container_names = {}
  for _, container in pairs(row.spec.template.spec.containers) do
    table.insert(container_names, container.name)
  end
  return table.concat(container_names, ",")
end

local function getImages(row)
  if not verifyContainers(row) then
    return ""
  end
  local images = {}
  for _, container in pairs(row.spec.template.spec.containers) do
    table.insert(images, container.image)
  end
  return table.concat(images, ",")
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  if rows and rows.items then
    for _, row in pairs(rows.items) do
      local pod = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        desired = getDesiredReplicas(row),
        current = getCurrentReplicas(row),
        ready = getReadyReplicas(row),
        age = time.since(row.metadata.creationTimestamp),
        containers = getContainers(row),
        images = getImages(row),
        selector = getSelectors(row),
      }

      table.insert(data, pod)
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "DESIRED",
    "CURRENT",
    "READY",
    "AGE",
    "CONTAINERS",
    "IMAGES",
    "SELECTOR",
  }

  return headers
end

return M
