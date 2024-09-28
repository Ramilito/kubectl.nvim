local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.helm.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

local function add_namespace(args, ns)
  if ns then
    if ns == "All" then
      table.insert(args, "-A")
    else
      table.insert(args, "-n")
      table.insert(args, ns)
    end
  end
  return args
end

local function get_args()
  local ns_filter = state.getNamespace()
  local args = add_namespace({ "ls", "-a", "--output", "json" }, ns_filter)
  return args
end

function M.View(cancellationToken)
  definition.url = get_args()
  ResourceBuilder:view(definition, cancellationToken, { cmd = definition.cmd, informer = false })
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "helm_desc_" .. name .. "_" .. ns,
    ft = "k8s_desc",
    url = { "status", name, "-n", ns, "--show-resources" },
    syntax = "yaml",
  }, { cmd = definition.cmd, reload = reload })
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
