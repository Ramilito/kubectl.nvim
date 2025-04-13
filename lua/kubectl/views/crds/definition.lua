local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")
local M = {}

--- Get the count of items in the provided data table
---@param row table
---@return string|table
local function getVersions(row)
  if not row or not row.spec or not row.spec.versions then
    return ""
  end
  local data = row.spec.versions
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
---@param rows {  }
---@return table[]
function M.processRow(rows)
  local data = {}

  if not rows then
    return data
  end
  for _, row in pairs(rows) do
    local crd = {
      name = row.metadata.name,
      group = row.spec and row.spec.group,
      kind = row.spec and row.spec.names and row.spec.names.kind,
      versions = getVersions(row),
      scope = row.spec and row.spec.scope,
      age = time.since(row.metadata.creationTimestamp),
    }

    table.insert(data, crd)
  end
  return data
end

return M
