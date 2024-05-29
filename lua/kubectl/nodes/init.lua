local M = {}
local time = require("kubectl.utils.time")
local find = require("kubectl.utils.find")

-- Define the custom match function for prefix and suffix
local function match_prefix_suffix(key, _, prefix, suffix)
  return key:match("^" .. prefix) or key:match(suffix .. "$")
end

local function getRole(row)
  local key, _ = find.dictionary(row.metadata.labels, function(key, value)
    return match_prefix_suffix(key, value, find.escape("node-role.kubernetes.io/"), find.escape("kubernetes.io/role"))
  end)

  if key then
    --TODO: Not sure if this handles the second kubernetes.io/role match
    local role = vim.split(key, "/")
    if #role == 2 then
      return role[2]
    end
  end
  return ""
end

local function getStatus(row)
  --TODO: Get status based on conditions
  return ""
end
function M.processRow(rows)
  local data = {}
  for _, row in pairs(rows.items) do
    local pod = {
      name = row.metadata.name,
      status = getStatus(row),
      roles = getRole(row),
      age = time.since(row.metadata.creationTimestamp),
      version = row.status.nodeInfo.kubeletVersion,
    }

    table.insert(data, pod)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "STATUS",
    "ROLES",
    "AGE",
    "VERSION",
  }

  return headers
end

return M
