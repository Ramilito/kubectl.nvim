local M = {}
local time = require("kubectl.utils.time")

--TODO: Get externalip
---@diagnostic disable-next-line: unused-local
local function getExternalIP(spec) -- luacheck: ignore
  return ""
end

function M.processRow(rows)
  local data = {}
  for _, row in ipairs(rows.items) do
    print(vim.inspect(row))
    local pod = {
      name = row.metadata.name,
      capacity = row.spec.capacity.storage,
      access = row.spec.accessModes,
      -- modes = row.,
      -- reclaim = getPorts(row.spec.ports),
      -- policy = getPorts(row.spec.ports),
      -- status = getPorts(row.spec.ports),
      -- claim = getPorts(row.spec.ports),
      -- storageclass = getPorts(row.spec.ports),
      -- reason = row.
      -- age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "CAPACITY",
    "ACCESS",
    "MODES",
    "RECLAIM",
    "POLICY",
    "STATUS",
    "CLAIM",
    "STORAGECLASS",
    "REASON",
    "AGE",
  }

  return headers
end

return M
