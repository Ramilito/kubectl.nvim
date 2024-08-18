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

  -- check if config.options.custom_views contains resource
  if config and config.options and config.options.custom_views and config.options.custom_views[M.resource] then
    local resource_config = config.options.custom_views[M.resource]
    definition.row_def = resource_config.headers or {}
    definition.display_name = resource_config.display_name or definition.display_name
    definition.url = resource_config.url or definition.url
    definition.ft = resource_config.ft or definition.ft
    definition.hints = resource_config.hints or definition.hints
    definition.cmd = resource_config.cmd or definition.cmd
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
