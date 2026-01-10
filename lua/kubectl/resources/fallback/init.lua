local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local commands = require("kubectl.actions.commands")
local describe_session = require("kubectl.views.describe.session")
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
  local sort_by = state.sortby[builder.definition.resource] and state.sortby[builder.definition.resource].current_word
    or nil
  local sort_order = state.sortby[builder.definition.resource] and state.sortby[builder.definition.resource].order
    or nil

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
      local loop = require("kubectl.utils.loop")
      loop.set_running(builder.buf_nr, false)
    end)
  end)
end

function M.Desc(name, ns, _)
  -- Use plural for the gvk.k as fallback resources need it
  local gvk = { k = M.definition.plural, g = M.definition.gvk.g, v = M.definition.gvk.v }
  describe_session.view(M.definition.resource, name, ns, gvk)
end

function M.Yaml(name, ns)
  local display_ns = ns and (" | " .. ns) or ""
  local title = M.definition.resource .. " | " .. name .. display_ns

  local def = {
    resource = M.definition.resource .. "_yaml",
    ft = "k8s_" .. M.definition.resource .. "_yaml",
    title = title,
    syntax = "yaml",
    cmd = "get_single_async",
    hints = {},
    panes = {
      { title = "YAML" },
    },
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_framed(def, {
    args = {
      gvk = M.definition.gvk,
      namespace = ns,
      name = name,
      output = "yaml",
    },
    recreate_func = M.Yaml,
    recreate_args = { name, ns },
  })
end

--- Get current seletion for view
---@return string|nil, string|nil
function M.getCurrentSelection()
  local name_col, ns_col = tables.getColumnIndices(M.definition.resource, M.definition.headers)
  if not name_col then
    return nil, nil
  end
  if ns_col then
    return tables.getCurrentSelection(name_col, ns_col)
  end
  return tables.getCurrentSelection(name_col), nil
end

return M
