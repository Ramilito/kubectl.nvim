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
  local resource = cached_resources.values[string.lower(kind)]

  if cache.loading then
    require("kubectl.views").view_or_fallback("pods")
    vim.notify("Fallback cache for " .. (kind or "<nil>") .. " is still loading, try again soon")

    return
  end

  if not resource then
    require("kubectl.views").view_or_fallback("pods")
    vim.notify("View not found: " .. (resource.name or "<nil>"))

    return
  end

  local ns = nil
  if state.ns and state.ns ~= "All" then
    ns = state.ns
  end

  M.definition.resource = string.lower(resource.plural)
  M.definition.display_name = string.upper(resource.name)
  M.definition.gvk = resource.gvk
  M.definition.ft = "k8s_" .. resource.name
  M.definition.crd_name = resource.crd_name

  local builder = ResourceBuilder:new(M.definition.resource)
  local filter = state.getFilter()
  local sort_by = state.sortby[M.definition.resource] and state.sortby[M.definition.resource].current_word or nil
  local sort_order = state.sortby[M.definition.resource] and state.sortby[M.definition.resource].order or nil

  builder.definition = M.definition

  if M.definition.informer and M.definition.informer.enabled then
    commands.run_async(
      "start_reflector_async",
      { M.definition.gvk.k, M.definition.gvk.g, M.definition.gvk.v, nil },
      function()
        commands.run_async(
          "get_fallback_table_async",
          { M.definition.crd_name, ns, sort_by, sort_order, filter },
          function(result)
            builder.data = result
            builder:decodeJson()
            builder.processedData = builder.data.rows
            builder.definition.headers = builder.data.headers
            M.definition.headers = builder.data.headers

            vim.schedule(function()
              builder:display(M.definition.ft, M.definition.resource, cancellationToken)
              builder:prettyPrint():addHints(M.definition.hints, true, true, true)
              builder:setContent(cancellationToken)
              builder:draw_header(cancellationToken)
              state.instance[M.definition.resource] = builder
            end)

            state.instance[M.definition.resource] = builder
            state.selections = {}
          end
        )
      end
    )
  end
end

function M.Draw(cancellationToken)
  -- state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
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
      M.definition.resource,
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
