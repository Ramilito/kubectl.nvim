local events = require("kubectl.utils.events")
local M = {}

--- All core ArgoCD CRD GVKs
M.argocd_resources = {
  {
    label = "Applications",
    gvk = { g = "argoproj.io", v = "v1alpha1", k = "Application" },
  },
  {
    label = "ApplicationSets",
    gvk = { g = "argoproj.io", v = "v1alpha1", k = "ApplicationSet" },
  },
  {
    label = "AppProjects",
    gvk = { g = "argoproj.io", v = "v1alpha1", k = "AppProject" },
  },
}

--- Ensure a field is a FieldValue table { value, symbol }
--- Rust fallback processor already returns FieldValue tables;
--- only wrap plain strings.
---@param field any
---@param color_fn function|nil Optional function to derive symbol from string value
---@return table
local function as_field_value(field, color_fn)
  local function colorize(value)
    if not color_fn then
      return nil
    end
    local symbol = color_fn(value)
    -- ColorStatus returns "" for unknown statuses; leave those unhighlighted
    -- rather than emitting an extmark with an empty highlight group.
    return symbol ~= "" and symbol or nil
  end

  if type(field) == "table" and field.value ~= nil then
    field.value = tostring(field.value):gsub("\n", " ")
    -- The Rust fallback processor emits FieldValue tables with symbol unset, so
    -- printer-column values arrive pre-wrapped and must be colored here.
    if field.symbol == nil or field.symbol == vim.NIL or field.symbol == "" then
      field.symbol = colorize(field.value)
    end
    return field
  end

  local str = tostring(field or ""):gsub("\n", " ")
  return {
    value = str,
    symbol = colorize(str),
  }
end

--- Pick the first present, non-empty value out of a list of candidate keys.
--- The Rust fallback processor (kubectl-client/src/processors/fallback.rs)
--- keys extra columns by the CRD's additionalPrinterColumn name, lowercased,
--- including spaces (e.g. "Sync Status" -> row["sync status"]). ArgoCD's
--- actual printer column names are unverified, so try several plausible
--- candidates in priority order.
---@param row table
---@param candidates string[]
---@return any|nil
local function pick(row, candidates)
  for _, key in ipairs(candidates) do
    local v = row[key]
    if v ~= nil and v ~= vim.NIL and v ~= "" then
      return v
    end
  end
  return nil
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
    local sync = pick(row, { "sync status", "sync", "status" })
    local health = pick(row, { "health status", "health" })
    local project = pick(row, { "project" })

    local entry = {
      namespace = row.namespace or "",
      name = row.name or "",
      sync = as_field_value(sync, function(s)
        return events.ColorStatus(s)
      end),
      health = as_field_value(health, function(s)
        return events.ColorStatus(s)
      end),
      project = as_field_value(project),
      age = as_field_value(row.age),
      _gvk = gvk,
    }
    table.insert(data, entry)
  end
  return data
end

return M
