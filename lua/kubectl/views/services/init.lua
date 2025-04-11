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
    syntax = "yaml",
    cmd = "describe_async",
  }, {
    args = { state.context["current-context"], M.definition.resource, ns, name, M.definition.gvk.g },
    reload = reload,
  })
end

function M.PortForward(name, ns)
  local def = {
    ft = "k8s_action",
    display = "PF: " .. name .. "-" .. "?",
    resource = name,
    ns = ns,
    resource_name = M.definition.resource_name,
    group = M.definition.group,
    version = M.definition.version,
  }

  commands.run_async("get_async", {
    M.definition.gvk.k,
    ns,
    name,
    def.syntax,
  }, function(data)
    local builder = ResourceBuilder:new("kubectl_pf")
    builder.data = data
    builder:decodeJson()
    local ports = {}
    for _, port in ipairs(builder.data.spec.ports) do
      table.insert(ports, {
        name = { value = port.name, symbol = hl.symbols.pending },
        port = { value = port.port, symbol = hl.symbols.success },
        protocol = port.protocol,
      })
    end
    if next(ports) == nil then
      ports[1] = { port = { value = "" }, name = { value = "" } }
    end

    vim.schedule(function()
      builder.data, builder.extmarks = tables.pretty_print(ports, { "NAME", "PORT", "PROTOCOL" })
      table.insert(builder.data, " ")
      local pf_data = {
        {
          text = "address:",
          value = "localhost",
          options = { "localhost", "0.0.0.0" },
          cmd = "",
          type = "positional",
        },
        { text = "local:", value = tostring(ports[1].port.value), cmd = "", type = "positional" },
        { text = "container port:", value = tostring(ports[1].port.value), cmd = ":", type = "merge_above" },
      }

      builder:action_view(def, pf_data, function(args)
        local client = require("kubectl.client")
        local local_port = args[2].value
        local remote_port = args[3].value
        client.portforward_start("service", name, ns, args[1], local_port, remote_port)
      end)
    end)
  end)
end

function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
