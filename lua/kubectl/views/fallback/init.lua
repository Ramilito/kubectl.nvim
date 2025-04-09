local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local utils = require("kubectl.utils.url")

local M = {
  resource = "fallback",
  definition = {
    ft = "k8s_fallback",
    gvk = { g = "", v = "v1", k = "pod" },
    informer = { enabled = true },
  },
}

function M.View(cancellationToken, resource)
  if resource then
    M.resource = resource
  elseif not M.resource then
    return
  end

  M.definition.display_name = M.resource
  M.definition.headers = { "NAME" }
  M.definition.hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected " .. M.resource },
  }

  local cached_resources = require("kubectl.cache").cached_api_resources
  local resource_name = cached_resources.values[M.resource] and M.resource or cached_resources.shortNames[M.resource]
  if resource_name then
    M.definition.resource = resource_name
    M.definition.gvk = cached_resources.values[resource_name].gvk
    M.definition.display_name = resource_name
    M.definition.namespaced = cached_resources.values[resource_name].namespaced
    M.definition.url = utils.replacePlaceholders(cached_resources.values[resource_name].url)
  end
  M.definition.cmd = "get_fallback_table_async"
  local ns = nil
  if state.ns and state.ns ~= "All" then
    ns = state.ns
  end

  M.definition.args = { resource_name, ns }
  local builder = ResourceBuilder:new(M.definition.resource)

  local filter = state.getFilter()
  local sort_by = state.sortby[M.definition.resource].current_word
  local sort_order = state.sortby[M.definition.resource].order

  builder.definition = M.definition
  commands.run_async(
    "get_fallback_table_async",
    { M.definition.resource, ns, sort_by, sort_order, filter },
    function(result)
      builder.data = result
      builder:decodeJson()
      builder.processedData = builder.data.rows
      builder.definition.headers = builder.data.headers

      if M.definition.informer and M.definition.informer.enabled then
        commands.run_async(
          "start_watcher_async",
          { M.definition.gvk.k, M.definition.gvk.g, M.definition.gvk.v, nil },
          function() end
        )
      end

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

function M.Draw(cancellationToken)
  -- state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = M.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    -- url = add_namespace({ "describe", M.resource .. "/" .. name }, ns),
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  local name_idx = tables.find_index(definition.headers, "NAME")
  local ns_idx = tables.find_index(definition.headers, "NAMESPACE")
  if ns_idx then
    return tables.getCurrentSelection(name_idx, ns_idx)
  end
  return tables.getCurrentSelection(name_idx)
end

return M
