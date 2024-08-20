local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.fallback.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}
M.resource = ""

local function get_args()
  local ns_filter = state.getNamespace()
  local args = { "get", M.resource, "-o=json" }
  if ns_filter == "All" then
    table.insert(args, "-A")
  else
    table.insert(args, "--namespace")
    table.insert(args, ns_filter)
  end
  return args
end

function M.View(cancellationToken, resource)
  if resource then
    M.resource = resource
  end

  definition.resource = M.resource
  definition.display_name = M.resource
  definition.url = get_args()
  definition.ft = "k8s_fallback"
  definition.hints = {
    { key = "<gd>", desc = "describe", long_desc = "Describe selected " .. M.resource },
  }
  definition.cmd = "kubectl"

  -- find resource in require("kubectl.views").cached_api_resources
  local cached_resources = require("kubectl.views").cached_api_resources
  local cached_resource = cached_resources.values[M.resource]
  if cached_resource ~= nil then
    definition.resource = cached_resources.values[M.resource].name
    definition.display_name = cached_resources.values[M.resource].name
    definition.url = {
      "-H",
      "Accept: application/json;as=Table;g=meta.k8s.io;v=v1",
      cached_resources.values[M.resource].url,
    }
    definition.cmd = "curl"
  end
  local resource_name = cached_resources.shortNames[M.resource]
  if resource_name then
    definition.resource = cached_resources.values[resource_name].name
    definition.display_name = cached_resources.values[resource_name].name
    definition.url = {
      "-H",
      "Accept: application/json;as=Table;g=meta.k8s.io;v=v1",
      cached_resources.values[resource_name].url,
    }
    definition.cmd = "curl"
  end

  ResourceBuilder:view(definition, cancellationToken, { cmd = definition.cmd })
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_fallback_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", M.resource .. "/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_fallback_desc", name, "yaml")
    :setCmd({ "describe", M.resource, name, "-n", ns })
    :fetch()
    :splitData()
    :setContentRaw()
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
