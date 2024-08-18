local time = require("kubectl.utils.time")
local M = {
  resource = "clusterrolebinding",
  display_name = "clusterrolebinding",
  ft = "k8s_clusterrolebinding",
  url = { "{{BASE}}/apis/rbac.authorization.k8s.io/v1/clusterrolebindings?pretty=false" },
  hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected clusterrolebinding" },
  },
}
local function getSubjects(data)
  local subjects = {}
  local kind = ""

  if data then
    for _, subject in ipairs(data) do
      if subject.kind == "ServiceAccount" then
        subject.kind = "SvcAcct"
      end
      kind = subject.kind
      table.insert(subjects, subject.name)
    end
    return kind, table.concat(subjects, ", ")
  end
  return "", ""
end

function M.processRow(rows)
  local data = {}

  for _, row in ipairs(rows.items) do
    local kind, subjects = getSubjects(row.subjects)
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
