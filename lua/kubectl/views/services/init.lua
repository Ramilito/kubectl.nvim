local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")
local hl = require("kubectl.actions.highlight")
local pf_definition = require("kubectl.views.port_forwards.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "services"
---@class ServicesModule
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "service" },
    informer = { enabled = true },
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
      { key = "<Plug>(kubectl.portforward)", desc = "Port forward", long_desc = "Port forward" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "TYPE",
      "CLUSTER-IP",
      "EXTERNAL-IP",
      "PORTS",
      "AGE",
    },
    processRow = definition.processRow,
  },
}

function M.View(cancellationToken)
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if state.instance[M.definition.resource] then
    local pfs = pf_definition.getPFRows()
    state.instance[M.definition.resource].extmarks_extra = {}
    pf_definition.setPortForwards(
      state.instance[M.definition.resource].extmarks_extra,
      state.instance[M.definition.resource].prettyData,
      pfs
    )
    state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
  end
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "services | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "svc", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

function M.PortForward(name, ns)
  local builder = ResourceBuilder:new("kubectl_pf")
  local pf_def = {
    ft = "k8s_action",
    display = "PF: " .. name .. "-" .. "?",
    resource = name,
    cmd = { "port-forward", "svc/" .. name, "-n", ns },
  }

  local kind = tables.find_resource(state.instance[M.definition.resource].data, name, ns)
  if not kind then
    return
  end
  local ports = {}
  for _, port in ipairs(kind.spec.ports) do
    table.insert(ports, {
      name = { value = port.name, symbol = hl.symbols.pending },
      port = { value = port.port, symbol = hl.symbols.success },
      protocol = port.protocol,
    })
  end
  if next(ports) == nil then
    ports[1] = { port = { value = "" }, name = { value = "" } }
  end
  builder.data, builder.extmarks = tables.pretty_print(ports, { "NAME", "PORT", "PROTOCOL" })
  table.insert(builder.data, " ")

  local data = {
    {
      text = "address:",
      value = "localhost",
      options = { "localhost", "0.0.0.0" },
      cmd = "--address",
      type = "option",
    },
    { text = "local:", value = tostring(ports[1].port.value), cmd = "", type = "positional" },
    { text = "container port:", value = tostring(ports[1].port.value), cmd = ":", type = "merge_above" },
  }

  builder:action_view(pf_def, data, function(args)
    commands.shell_command_async("kubectl", args)
    vim.schedule(function()
      M.View()
    end)
  end)
end

function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
