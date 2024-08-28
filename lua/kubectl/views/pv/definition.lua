local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {
  resource = "pv",
  display_name = "PersistentVolumes",
  ft = "k8s_pv",
  url = { "{{BASE}}/api/v1/persistentvolumes?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.describe)", desc = "describe", long_desc = "Describe selected pv" },
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
  return { symbol = events.ColorStatus(phase), value = phase }
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  for _, row in ipairs(rows.items) do
    local pod = {
      name = row.metadata.name,
      capacity = row.spec.capacity.storage,
      ["access modes"] = getAccessModes(row.spec.accessModes),
      ["reclaim policy"] = row.spec.persistentVolumeReclaimPolicy,
      status = getPhase(row),
      claim = row.spec.claimRef.name,
      ["storage class"] = row.spec.storageClassName,
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
    "ACCESS MODES",
    "RECLAIM POLICY",
    "STATUS",
    "CLAIM",
    "STORAGE CLASS",
    "REASON",
    "AGE",
  }

  return headers
end

return M
