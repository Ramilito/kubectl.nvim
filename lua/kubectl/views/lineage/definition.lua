local M = {

  resource = "lineage",
  display_name = "Lineage",
  ft = "k8s_lineage",
}

local function getPods(rows)
  local data = {}
  for _, row in ipairs(rows.items) do
    table.insert(data, { name = row.metadata.name, ownerReferences = row.metadata.ownerReferences })
  end
  return data
end
local function getReplicasets(rows) end
local function getDeployments(rows) end

function M.processRow(rows)
  local pods = rows[1]
  local replicasets = rows[2]
  local deployments = rows[3]

  local data = {
    pods = getPods(pods),
    replicasets = getReplicasets(replicasets),
    deployments = getDeployments(deployments),
  }

  return data
end

return M
