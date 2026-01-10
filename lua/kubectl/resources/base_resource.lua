local describe_session = require("kubectl.views.describe.session")
local manager = require("kubectl.resource_manager")
local tables = require("kubectl.utils.tables")

local BaseResource = {}

--- Create a new resource module based on BaseResource
---@param definition table The resource definition table
---@param options? table Optional configuration (is_cluster_scoped)
---@return table The resource module with View, Draw, Desc, getCurrentSelection
function BaseResource.extend(definition, options)
  options = options or {}

  -- Auto-detect cluster-scoped from headers (no NAMESPACE = cluster-scoped)
  local is_cluster_scoped = options.is_cluster_scoped
  if is_cluster_scoped == nil then
    is_cluster_scoped = not vim.tbl_contains(definition.headers or {}, "NAMESPACE")
  end

  local M = {
    definition = definition,
    _options = {
      is_cluster_scoped = is_cluster_scoped,
    },
  }

  --- View the resource list
  ---@param cancellationToken function|nil
  function M.View(cancellationToken)
    local builder = manager.get_or_create(M.definition.resource)
    builder.view(M.definition, cancellationToken)
  end

  --- Draw/refresh the resource list
  ---@param cancellationToken function|nil
  function M.Draw(cancellationToken)
    local builder = manager.get(M.definition.resource)
    if builder then
      if M.onBeforeDraw then
        M.onBeforeDraw(builder)
      end
      builder.draw(cancellationToken)
    end
  end

  --- Describe a specific resource
  ---@param name string Resource name
  ---@param ns string|nil Namespace (nil for cluster-scoped)
  ---@param _ boolean|nil Whether to reload (deprecated, kept for API compatibility)
  function M.Desc(name, ns, _)
    local gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v }
    local namespace = M._options.is_cluster_scoped and nil or ns
    describe_session.view(M.definition.resource, name, namespace, gvk)
  end

  --- View YAML for a specific resource
  ---@param name string Resource name
  ---@param ns string|nil Namespace (nil for cluster-scoped)
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
        namespace = M._options.is_cluster_scoped and nil or ns,
        name = name,
        output = "yaml",
      },
      recreate_func = M.Yaml,
      recreate_args = { name, ns },
    })
  end

  --- Get current selection from buffer
  ---@return string|nil ... Returns name and optionally namespace
  function M.getCurrentSelection()
    local name_col, ns_col = tables.getColumnIndices(M.definition.resource, M.definition.headers or {})
    if not name_col then
      return nil
    end
    if ns_col then
      return tables.getCurrentSelection(name_col, ns_col)
    else
      return tables.getCurrentSelection(name_col)
    end
  end

  return M
end

return BaseResource
