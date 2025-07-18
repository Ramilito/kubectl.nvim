local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  resource = "fallback",
  definition = {
    ft = "k8s_fallback",
    gvk = {},
  },
}

function M.View(cancellationToken, kind)
  local cached_resources = cache.cached_api_resources
  if kind then
    M.resource = kind
  end

  local resource = cached_resources.values[string.lower(M.resource)]
    or cached_resources.shortNames[string.lower(M.resource)]

  if not resource then
    require("kubectl.views").resource_or_fallback("pods")
    vim.notify("View not found in cache: " .. (kind or "<nil>"))

    return
  end

  M.definition.resource = string.lower(resource.name)
  M.definition.display_name = string.upper(resource.name)
  M.definition.gvk = resource.gvk
  M.definition.ft = "k8s_" .. resource.name
  M.definition.plural = resource.plural
  M.definition.crd_name = resource.crd_name

  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.buf_nr, builder.win_nr = buffers.buffer(builder.definition.ft, resource.name)

  commands.run_async("start_reflector_async", { gvk = M.definition.gvk, namespace = nil }, function()
    vim.schedule(function()
      M.Draw(cancellationToken)
      vim.cmd("doautocmd User K8sDataLoaded")
      state.selections = {}
    end)
  end)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)

  if not builder then
    return
  end

  local ns = nil
  if state.ns and state.ns ~= "All" then
    ns = state.ns
  end

  local filter = state.getFilter()
  local filter_label = state.getFilterLabel()
  local filter_key = state.getFilterKey()
  local sort_by = state.sortby[builder.definition.resource].current_word
  local sort_order = state.sortby[builder.definition.resource].order

  commands.run_async("get_fallback_table_async", {
    gvk = builder.definition.gvk,
    namespace = ns,
    sort_by = sort_by,
    sort_order = sort_order,
    filter = filter,
    filter_label = filter_label,
    filter_key = filter_key,
  }, function(result)
    if not result then
      return
    end
    builder.data = result
    builder.decodeJson()
    builder.processedData = builder.data.rows
    builder.definition.headers = builder.data.headers
    builder.sort()

    vim.schedule(function()
      local windows = buffers.get_windows_by_name(builder.definition.resource)
      for _, win_id in ipairs(windows) do
        builder.prettyPrint(win_id).addDivider(true).addHints(builder.definition.hints, true, true)
        builder.displayContent(win_id, cancellationToken)
      end
    end)
  end)
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

  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      context = state.context["current-context"],
      gvk = { k = M.definition.plural, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = ns,
      name = name,
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
