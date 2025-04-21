local events = require("kubectl.utils.events")
local time = require("kubectl.utils.time")
local M = {}

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

  if not rows then
    return data
  end
  for _, row in ipairs(rows) do
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

return M
