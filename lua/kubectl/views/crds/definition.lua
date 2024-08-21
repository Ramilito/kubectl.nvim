local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")
local M = {
  resource = "crds",
  display_name = "CRDS",
  ft = "k8s_crds",
  url = { "{{BASE}}/apis/apiextensions.k8s.io/v1/customresourcedefinitions?pretty=false" },
  hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected CRD" },
  },
}

--- Get the count of items in the provided data table
---@param data table
---@return string|table
local function getVersions(data)
  local versions = ""
  local has_deprecated = false
  for _, version in ipairs(data) do
    if versions ~= "" then
      versions = versions .. ","
    end
    versions = versions .. version.name
    if version.deprecated then
      has_deprecated = true
      versions = versions .. "!"
    end
  end
  if has_deprecated then
    return { value = versions, symbol = hl.symbols.error }
  end
  return versions
end

--- Process rows and transform them into a structured table
---@param rows { items: table[] }
---@return table[]
function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end
  for _, row in pairs(rows.items) do
    local pod = {
      name = row.metadata.name,
      group = row.spec.group,
      kind = row.spec.names.kind,
      versions = getVersions(row.spec.versions),
      scope = row.spec.scope,
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, pod)
  end
  return data
end

--- Get the headers for the processed data table
---@return string[]
function M.getHeaders()
  local headers = {
    "NAME",
    "GROUP",
    "KIND",
    "VERSIONS",
    "SCOPE",
    "AGE",
  }

  return headers
end

return M
