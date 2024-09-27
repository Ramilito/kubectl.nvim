local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.fallback.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {
  resource = "",
  configure_definition = true,
}

local function add_namespace(args, ns)
  if ns then
    if ns == "All" then
      table.insert(args, "--all-namespaces")
    else
      table.insert(args, "-n")
      table.insert(args, ns)
    end
  end
  return args
end

local function get_args()
  local ns_filter = state.getNamespace()
  local args = add_namespace({ "get", M.resource, "-o=json" }, ns_filter)
  return args
end

function M.View(cancellationToken, resource)
  if resource then
    M.resource = resource
  elseif not M.resource then
    return
  end

  -- default fallback values
  if M.configure_definition then
    definition.resource = M.resource
    definition.display_name = M.resource
    definition.url = get_args()
    definition.ft = "k8s_fallback"
    definition.headers = { "NAME" }
    definition.hints = {
      { key = "<gd>", desc = "describe", long_desc = "Describe selected " .. M.resource },
    }
    definition.cmd = "kubectl"

    -- cached resources fallback values
    local cached_resources = require("kubectl.views").cached_api_resources
    local resource_name = cached_resources.values[M.resource] and M.resource or cached_resources.shortNames[M.resource]
    if resource_name and not M.configured_curl then
      definition.resource = resource_name
      definition.display_name = resource_name
      definition.url = {
        "-H",
        "Accept: application/json;as=Table;g=meta.k8s.io;v=v1",
        cached_resources.values[resource_name].url,
      }
      definition.cmd = "curl"
      definition.namespaced = cached_resources.values[resource_name].namespaced
    end
  end

  ResourceBuilder:view(definition, cancellationToken, { cmd = definition.cmd })
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_fallback_edit", name, "yaml")
  commands.execute_terminal("kubectl", add_namespace({ "edit", M.resource .. "/" .. name }, ns))
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = M.resource .. "_desc_" .. name .. "_" .. ns,
    ft = "k8s_desc",
    url = add_namespace({ "describe", M.resource .. "/" .. name }, ns),
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
