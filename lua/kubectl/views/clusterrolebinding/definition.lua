local time = require("kubectl.utils.time")
local M = {
  resource = "clusterrolebinding",
  display_name = "clusterrolebinding",
  ft = "k8s_clusterrolebinding",
  url = { "{{BASE}}/apis/rbac.authorization.k8s.io/v1/clusterrolebindings?pretty=false" },
}
local hl = require("kubectl.actions.highlight")

local function getSubjects(row)
  if not row or not row.subjects then
    return "", ""
  end
  local data = row.subjects
  local subjects = {}
  local kind = { symbol = "", value = "" }

  for _, subject in ipairs(data) do
    kind.value = subject.kind
    if kind.value == "ServiceAccount" then
      kind.symbol = hl.symbols.success
      kind.value = "SvcAcct"
    elseif kind.value == "User" then
      kind.symbol = hl.symbols.note
    elseif kind.value == "Group" then
      kind.symbol = hl.symbols.debug
    end
    table.insert(subjects, subject.name)
  end
  return kind, table.concat(subjects, ", ")
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  for _, row in ipairs(rows.items) do
    local kind, subjects = getSubjects(row)
    local role = {
      name = row.metadata.name,
      role = row.roleRef.name,
      ["subject-kind"] = kind,
      subjects = subjects,
      age = time.since(row.metadata.creationTimestamp, true),
    }
    table.insert(data, role)
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAME",
    "ROLE",
    "SUBJECT-KIND",
    "SUBJECTS",
    "AGE",
  }

  return headers
end

return M
