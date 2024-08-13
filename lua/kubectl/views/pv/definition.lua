local time = require("kubectl.utils.time")
local M = {
  resource = "pv",
  display_name = "PV",
  ft = "k8s_pv",
  url = { "{{BASE}}/api/v1/persistentvolumes?pretty=false" },
  hints = {},
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

  for _, row in ipairs(rows.items) do
    local pod = {
      name = row.metadata.name,
      capacity = row.spec.capacity.storage,
      accessmodes = getAccessModes(row.spec.accessModes),
      reclaimpolicy = row.spec.persistentVolumeReclaimPolicy,
      status = getPhase(row),
      claim = row.spec.claimRef.name,
      storageclass = row.spec.storageClassName,
      reason = row.status.reason or "",
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "CAPACITY",
    "ACCESSMODES",
    "RECLAIMPOLICY",
    "STATUS",
    "CLAIM",
    "STORAGECLASS",
    "REASON",
    "AGE",
  }

  return headers
end

return M
