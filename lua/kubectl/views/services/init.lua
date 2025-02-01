local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.services.definition")
local hl = require("kubectl.actions.highlight")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = { builder = nil, pfs = {} }

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true)
  ResourceBuilder:view(definition, cancellationToken)
end

function M.Draw(cancellationToken)
  state.instance:draw(definition, cancellationToken)
  root_definition.setPortForwards(state.instance.extmarks, state.instance.prettyData, M.pfs)
end

function M.Desc(name, ns, reload)
  ResourceBuilder:view_float({
    resource = "svc | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    url = { "describe", "svc", name, "-n", ns },
    syntax = "yaml",
  }, { cmd = "kubectl", reload = reload })
end

function M.PortForward(name, ns)
  local builder = ResourceBuilder:new("kubectl_pf")
  local pf_def = {
    ft = "k8s_svc_pf",
    display = "PF: " .. name .. "-" .. "?",
    resource = name,
    cmd = { "port-forward", "svc/" .. name, "-n", ns },
  }

  local resource = tables.find_resource(state.instance.data, name, ns)
  if not resource then
    return
  end
  local ports = {}
  for _, port in ipairs(resource.spec.ports) do
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

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
