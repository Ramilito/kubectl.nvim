local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.resources.argocd.definition")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  definition = {
    resource = "argocd",
    display_name = "ArgoCD",
    ft = "k8s_argocd",
    gvk = definition.gvk,
    hints = {
      { key = "<Plug>(kubectl.describe)", desc = "desc", long_desc = "Describe resource" },
      { key = "<Plug>(kubectl.yaml)", desc = "yaml", long_desc = "View YAML" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "SYNC",
      "HEALTH",
      "AUTOSYNC",
      "OWNER",
      "PROJECT",
      "AGE",
    },
  },
}

--- Namespace to scope every fetch to, or nil for all namespaces.
---@return string|nil
local function current_namespace()
  if state.ns and state.ns ~= "All" then
    return state.ns
  end
  return nil
end

--- Context+namespace the reflector was last started for, so a `:Kubens` or
--- context switch triggers a restart on the next Draw.
local reflector_started = nil

--- Start the Application reflector in the background, once per
--- context+namespace. Draw never waits on it: until the initial sync lands,
--- get_all_async falls back to a live list, and later refreshes read the
--- store for free.
---@param ns string|nil
local function ensure_reflector(ns)
  local ctx = state.context["current-context"] or ""
  local target = ctx .. "|" .. (ns or "<all>")
  if reflector_started == target then
    return
  end
  reflector_started = target
  commands.run_async("start_reflector_async", { gvk = definition.gvk, namespace = ns }, function() end)
end

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.buf_nr, builder.win_nr = buffers.buffer(M.definition.ft, builder.resource)
  M.Draw(cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if not builder then
    return
  end

  local ns = current_namespace()
  local sort_data = state.sortby[M.definition.resource]

  commands.run_async("get_all_async", { gvk = definition.gvk, namespace = ns }, function(data, err)
    vim.schedule(function()
      local loop = require("kubectl.utils.loop")
      if err or not data then
        loop.set_running(builder.buf_nr, false)
        return
      end
      -- Only start the watch once the kind is known to be served: a
      -- reflector for a missing CRD would retry forever.
      ensure_reflector(ns)

      builder.data = data
      builder.decodeJson()
      builder.process(definition.processRow)
      if sort_data then
        builder.sort()
      end

      local windows = buffers.get_windows_by_name(M.definition.resource)
      for _, win_id in ipairs(windows) do
        builder.prettyPrint(win_id).addDivider(true).addHints(M.definition.hints, true, true)
        builder.displayContent(win_id, cancellationToken)
      end
      loop.set_running(builder.buf_nr, false)
    end)
  end)
end

function M.Desc(name, ns)
  local describe_session = require("kubectl.views.describe.session")
  describe_session.view(M.definition.resource, name, ns, definition.gvk)
end

function M.Yaml(name, ns)
  local display_ns = ns and (" | " .. ns) or ""
  local title = M.definition.resource .. " | " .. name .. display_ns

  local def = {
    resource = M.definition.resource .. "_yaml",
    ft = "k8s_yaml",
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
      gvk = definition.gvk,
      namespace = ns,
      name = name,
      output = "yaml",
    },
    recreate_func = M.Yaml,
    recreate_args = { name, ns },
  })
end

--- Get current selection from buffer
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
