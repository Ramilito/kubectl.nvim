local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local M = {}

--- All core ArgoCD CRD GVKs.
--- `fetch_raw` marks kinds whose columns cannot be served by the fallback
--- table alone; `autosync_path` locates that kind's `syncPolicy.automated`
--- block within the raw object. AppProjects need neither.
M.argocd_resources = {
  {
    label = "Applications",
    gvk = { g = "argoproj.io", v = "v1alpha1", k = "Application" },
    fetch_raw = true,
    autosync_path = { "spec", "syncPolicy", "automated" },
  },
  {
    label = "ApplicationSets",
    gvk = { g = "argoproj.io", v = "v1alpha1", k = "ApplicationSet" },
    fetch_raw = true,
    autosync_path = { "spec", "template", "spec", "syncPolicy", "automated" },
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

--- Walk a path of keys, bailing out as soon as a segment is missing.
---@param obj any
---@param path string[]
---@return any|nil
local function dig(obj, path)
  local node = obj
  for _, key in ipairs(path) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
    if node == nil or node == vim.NIL then
      return nil
    end
  end
  return node
end

--- Render a `syncPolicy.automated` block the way ArgoCD interprets it: an
--- absent block means manual sync, and `enabled: false` (ArgoCD 3.x) switches
--- an otherwise-configured policy back off.
---@param automated table|nil
---@return string
function M.getAutoSync(automated)
  if type(automated) ~= "table" or automated.enabled == false then
    return "Manual"
  end
  return "Auto"
end

--- Auto-sync is a configuration choice, not a health signal, so only the "on"
--- state is highlighted; manual stays muted.
---@param value string
---@return string
local function autosync_symbol(value)
  if value == "Auto" then
    return hl.symbols.success
  elseif value == "Manual" then
    return hl.symbols.gray
  end
  return ""
end

--- Name the controller that created this object. ArgoCD sets an
--- ApplicationSet owner reference on every Application it generates, so an
--- owner here means the app is generated and edits to it will be reverted.
--- Apps applied from Git or created by hand carry no owner reference.
---@param meta table Object metadata
---@return string
function M.getOwner(meta)
  local refs = meta.ownerReferences
  if type(refs) ~= "table" then
    return ""
  end
  for _, ref in ipairs(refs) do
    if type(ref) == "table" and ref.name then
      if ref.kind == "ApplicationSet" then
        return ref.name
      end
      -- Any other controller is unexpected here, so name the kind too
      return (ref.kind or "?") .. "/" .. ref.name
    end
  end
  return ""
end

--- Build a `namespace/name` -> extra-columns lookup from raw objects. These
--- columns are not additionalPrinterColumns on either CRD, so they can only
--- come from the full object.
---@param objects table|nil Decoded list of objects from get_all_async
---@param autosync_path string[]|nil Path to the `automated` block, if the kind has one
---@return table<string, { autosync: string, owner: string }>
function M.buildRowExtras(objects, autosync_path)
  local lookup = {}
  if type(objects) ~= "table" then
    return lookup
  end
  for _, obj in ipairs(objects) do
    local meta = type(obj) == "table" and obj.metadata or nil
    if type(meta) == "table" and meta.name then
      lookup[(meta.namespace or "") .. "/" .. meta.name] = {
        autosync = autosync_path and M.getAutoSync(dig(obj, autosync_path)) or "",
        owner = M.getOwner(meta),
      }
    end
  end
  return lookup
end

--- Process rows from fallback table into normalized display rows
---@param rows table Raw rows from get_fallback_table_async
---@param gvk table GVK info to attach to each row
---@param extras_by_key table<string, { autosync: string, owner: string }>|nil From M.buildRowExtras
---@return table
function M.processRow(rows, gvk, extras_by_key)
  local data = {}
  if not rows then
    return data
  end
  extras_by_key = extras_by_key or {}
  for _, row in ipairs(rows) do
    local sync = pick(row, { "sync status", "sync", "status" })
    local health = pick(row, { "health status", "health" })
    local project = pick(row, { "project" })
    local namespace = row.namespace or ""
    local name = row.name or ""
    local extras = extras_by_key[namespace .. "/" .. name] or {}

    local entry = {
      namespace = namespace,
      name = name,
      sync = as_field_value(sync, function(s)
        return events.ColorStatus(s)
      end),
      health = as_field_value(health, function(s)
        return events.ColorStatus(s)
      end),
      autosync = as_field_value(extras.autosync or "", autosync_symbol),
      owner = as_field_value(extras.owner or ""),
      project = as_field_value(project),
      age = as_field_value(row.age),
      _gvk = gvk,
    }
    table.insert(data, entry)
  end
  return data
end

return M
