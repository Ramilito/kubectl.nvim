local time = require("kubectl.utils.time")
local M = {
  resource = "pvc",
  display_name = "pvc",
  ft = "k8s_pvc",
  url = { "{{BASE}}/api/v1/{{NAMESPACE}}persistentvolumeclaims?pretty=false" },
  hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected pvc" },
  },
}

local function getAccessModes(data)
  local modes = {}

  for _, value in ipairs(data) do
    if value == "ReadWriteOnce" then
      table.insert(modes, "RWO")
    elseif value == "ReadOnlyMany" then
      table.insert(modes, "ROX")
    elseif value == "ReadWriteMany" then
      table.insert(modes, "RWX")
    elseif value == "ReadWriteOncePod" then
      table.insert(modes, "RWOP")
    end
  end
  return table.concat(modes, ", ")
end

local function getPhase(row)
  local phase = row.status.phase
  if row.metadata.deletionTimestamp then
    phase = "Terminating"
  end
  return phase
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end
  for _, row in ipairs(rows.items) do
    local pod = {
      namespace = row.metadata.namespace,
      name = row.metadata.name,
      status = getPhase(row),
      volume = row.spec.volumeName,
      capacity = row.spec.resources.requests.storage,
      ["access modes"] = getAccessModes(row.spec.accessModes),
      ["storage class"] = row.spec.storageClassName,
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "STATUS",
    "VOLUME",
    "CAPACITY",
    "ACCESS MODES",
    "STORAGE CLASS",
    "AGE",
  }

  return headers
end

return M
