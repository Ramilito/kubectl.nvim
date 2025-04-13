local ResourceBuilder = require("kubectl.resourcebuilder")
local cache = require("kubectl.cache")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  resource = "fallback",
  definition = {
    ft = "k8s_fallback",
    informer = { enabled = true },
    gvk = {},
  },
}

function M.View(cancellationToken, kind)
  local cached_resources = cache.cached_api_resources
  if kind then
    M.resource = kind
  end
  local resource = cached_resources.values[string.lower(M.resource)]

  if cache.loading then
    require("kubectl.views").view_or_fallback("pods")
    vim.notify("Fallback cache for " .. (M.resource or "<nil>") .. " is still loading, try again soon")

    return
  end

  if not resource then
    require("kubectl.views").view_or_fallback("pods")
    vim.notify("View not found: " .. (resource.name or "<nil>"))

    return
  end

  M.definition.resource = string.lower(resource.name)
  M.definition.display_name = string.upper(resource.name)
  M.definition.gvk = resource.gvk
  M.definition.ft = "k8s_" .. resource.name
  M.definition.plural = resource.plural
  M.definition.crd_name = resource.crd_name

  local instance = ResourceBuilder:new(M.definition.resource)
  instance.definition = M.definition

  commands.run_async(
    "start_reflector_async",
    { M.definition.gvk.k, M.definition.gvk.g, M.definition.gvk.v, nil },
    function()
      vim.schedule(function()
        instance:display(M.definition.ft, M.definition.resource, cancellationToken)
        M.Draw(cancellationToken)
        state.selections = {}
      end)
      state.instance[M.definition.resource] = nil
      state.instance[M.definition.resource] = instance
    end
  )
end

function M.Draw(cancellationToken)
  if not state.instance[M.definition.resource] then
    return
  end

  local instance = state.instance[M.definition.resource]
  instance.definition = M.definition

  local ns = nil
  if state.ns and state.ns ~= "All" then
    ns = state.ns
  end

  local filter = state.getFilter()
  local sort_by = state.sortby[instance.definition.resource].current_word
  local sort_order = state.sortby[instance.definition.resource].order

  commands.run_async(
    "get_fallback_table_async",
    { M.definition.crd_name, ns, sort_by, sort_order, filter },
    function(result)
      instance.data = result
      instance:decodeJson()
      instance.processedData = instance.data.rows
      instance.definition.headers = instance.data.headers
      M.definition.headers = instance.data.headers

      vim.schedule(function()
        instance:display(M.definition.ft, M.definition.resource, cancellationToken)
        instance:prettyPrint():addHints(M.definition.hints, true, true, true)
        instance:setContent(cancellationToken)
        instance:draw_header(cancellationToken)
        state.instance[M.definition.resource] = nil
        state.instance[M.definition.resource] = instance
      end)
    end
  )
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. " | " .. name,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }

  if ns then
    def.resource = def.resource .. " | " .. ns
  end

  ResourceBuilder:view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.plural,
      ns,
      name,
      M.definition.gvk.g,
      M.definition.gvk.v,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  local name_idx = tables.find_index(M.definition.headers, "NAME")
  local ns_idx = tables.find_index(M.definition.headers, "NAMESPACE")
  if ns_idx then
    return tables.getCurrentSelection(name_idx, ns_idx)
  end
  return tables.getCurrentSelection(name_idx)
end

return M
