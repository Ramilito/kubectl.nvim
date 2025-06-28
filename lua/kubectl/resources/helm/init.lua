local definition = require("kubectl.resources.helm.definition")
local manager = require("kubectl.resource_manager")
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
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(definition, cancellationToken, { cmd = definition.cmd, informer = false })
end

function M.Draw(cancellationToken)
  state.instance[definition.resource]:draw(definition, cancellationToken)
end

function M.Desc(name, ns, reload)
  local builder = manager.get(definition.resource)
  if not builder then
    return
  end
  builder.view_float({
    resource = "helm | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "status", name, "-n", ns, "--show-resources" },
    syntax = "yaml",
  }, { cmd = definition.cmd, reload = reload })
end

function M.Yaml(name, ns)
  if name then
    local def = {
      resource = "helm" .. " | " .. name,
      ft = "k8s_yaml",
      url = { "get", "manifest", name },
      syntax = "yaml",
    }
    if ns then
      table.insert(def.url, "-n")
      table.insert(def.url, ns)
      def.resource = def.resource .. " | " .. ns
    end

    local builder = manager.get(definition.resource)
    if not builder then
      return
    end
    builder.view_float(def, { cmd = "helm" })
  end
end

function M.Values(name, ns)
  if name then
    local def = {
      resource = "helm" .. " | " .. name,
      ft = "k8s_yaml",
      url = { "get", "values", name },
      syntax = "yaml",
    }
    if ns then
      table.insert(def.url, "-n")
      table.insert(def.url, ns)
      def.resource = def.resource .. " | " .. ns
    end
    local builder = manager.get(definition.resource)
    if not builder then
      return
    end
    builder.view_float(def, { cmd = "helm" })
  end
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
