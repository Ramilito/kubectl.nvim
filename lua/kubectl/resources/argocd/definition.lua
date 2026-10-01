local events = require("kubectl.utils.events")
local hl = require("kubectl.actions.highlight")
local time = require("kubectl.utils.time")
local M = {}

--- The one kind this view lists. ApplicationSets and AppProjects are shown as
--- columns on each Application row (OWNER and PROJECT), not as peer listings.
M.gvk = { g = "argoproj.io", v = "v1alpha1", k = "Application" }

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

--- Wrap a plain value as a FieldValue table, optionally colored.
---@param value any
---@param color_fn function|nil
---@return table
local function field(value, color_fn)
  local str = tostring(value or ""):gsub("\n", " ")
  local symbol
  if color_fn and str ~= "" then
    local s = color_fn(str)
    -- Unknown statuses color as ""; leave those unhighlighted rather than
    -- emitting an extmark with an empty highlight group.
    symbol = s ~= "" and s or nil
  end
  return { value = str, symbol = symbol }
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

--- Name the controller that created this Application. ArgoCD sets an
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

--- Build display rows straight from raw Application objects. Every column's
--- source lives on the object itself, so no printer-column table is needed.
---@param objects table|nil Decoded list from get_all_async
---@return table
function M.processRow(objects)
  local data = {}
  if type(objects) ~= "table" then
    return data
  end
  for _, obj in ipairs(objects) do
    local meta = type(obj) == "table" and obj.metadata or nil
    if type(meta) == "table" and meta.name then
      table.insert(data, {
        namespace = meta.namespace or "",
        name = meta.name,
        sync = field(dig(obj, { "status", "sync", "status" }), events.ColorStatus),
        health = field(dig(obj, { "status", "health", "status" }), events.ColorStatus),
        autosync = field(M.getAutoSync(dig(obj, { "spec", "syncPolicy", "automated" })), autosync_symbol),
        owner = field(M.getOwner(meta)),
        project = field(dig(obj, { "spec", "project" })),
        age = time.since(meta.creationTimestamp) or { value = "", symbol = "" },
      })
    end
  end
  return data
end

return M
