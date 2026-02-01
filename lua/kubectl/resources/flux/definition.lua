local events = require("kubectl.utils.events")
local M = {}

--- All core Flux CRD GVKs
M.flux_resources = {
  {
    label = "GitRepository",
    gvk = { g = "source.toolkit.fluxcd.io", v = "v1", k = "GitRepository" },
  },
  {
    label = "Kustomization",
    gvk = { g = "kustomize.toolkit.fluxcd.io", v = "v1", k = "Kustomization" },
  },
  {
    label = "HelmRelease",
    gvk = { g = "helm.toolkit.fluxcd.io", v = "v2", k = "HelmRelease" },
  },
  {
    label = "HelmRepository",
    gvk = { g = "source.toolkit.fluxcd.io", v = "v1", k = "HelmRepository" },
  },
  {
    label = "OCIRepository",
    gvk = { g = "source.toolkit.fluxcd.io", v = "v1beta2", k = "OCIRepository" },
  },
  {
    label = "Bucket",
    gvk = { g = "source.toolkit.fluxcd.io", v = "v1beta2", k = "Bucket" },
  },
  {
    label = "HelmChart",
    gvk = { g = "source.toolkit.fluxcd.io", v = "v1", k = "HelmChart" },
  },
}

--- Ensure a field is a FieldValue table { value, symbol }
--- Rust fallback processor already returns FieldValue tables;
--- only wrap plain strings.
---@param field any
---@param color_fn function|nil Optional function to derive symbol from string value
---@return table
local function as_field_value(field, color_fn)
  if type(field) == "table" and field.value ~= nil then
    field.value = tostring(field.value):gsub("\n", " ")
    return field
  end
  local str = tostring(field or ""):gsub("\n", " ")
  return {
    value = str,
    symbol = color_fn and color_fn(str) or "",
  }
end

--- Process rows from fallback table into normalized display rows
---@param rows table Raw rows from get_fallback_table_async
---@param gvk table GVK info to attach to each row
---@return table
function M.processRow(rows, gvk)
  local data = {}
  if not rows then
    return data
  end
  for _, row in ipairs(rows) do
    local entry = {
      namespace = row.namespace or "",
      name = row.name or "",
      ready = as_field_value(row.ready, M.getReadySymbol),
      status = as_field_value(row.status, function(s)
        return events.ColorStatus(s)
      end),
      age = as_field_value(row.age),
      _gvk = gvk,
    }
    table.insert(data, entry)
  end
  return data
end

--- Map a Ready string value to a highlight symbol
---@param ready_value string
---@return string
function M.getReadySymbol(ready_value)
  if not ready_value or ready_value == "" then
    return ""
  end
  local val = string.lower(ready_value)
  if val == "true" then
    return events.ColorStatus("True")
  elseif val == "false" then
    return events.ColorStatus("False")
  end
  return ""
end

return M
