local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local pf_definition = require("kubectl.resources.port_forwards.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "services"
---@class ServicesModule
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "Service" },
    child_view = {
      name = "pods",
      predicate = function(name, ns)
        local client = require("kubectl.client")
        local svc =
          client.get_single(vim.json.encode({ kind = "Service", namespace = ns, name = name, output = "Json" }))

        local svc_decoded = vim.json.decode(svc)
        if svc_decoded.spec.type == "ExternalName" then
          vim.notify(
            "Service " .. name .. " in namespace " .. ns .. " is of type ExternalName, no pods to show.",
            vim.log.levels.WARN
          )
          return ""
        end

        local labels = svc_decoded.spec.selector
        local parts = {}
        for k, v in pairs(labels) do
          table.insert(parts, ("metadata.labels.%s=%s"):format(k, v))
        end

        return table.concat(parts, ",")
      end,
    },
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
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    local pfs = pf_definition.getPFRows(string.lower(M.definition.gvk.k))
    builder.extmarks_extra = {}
    pf_definition.setPortForwards(builder.extmarks_extra, builder.prettyData, pfs)
    builder.draw(cancellationToken)
  end
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      context = state.context["current-context"],
      gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = ns,
      name = name,
    },
    reload = reload,
  })
end

function M.PortForward(name, ns)
  local def = {
    resource = "svc_pf",
    display = "PF: " .. name .. "-" .. "?",
    ft = "k8s_action",
    ns = ns,
    group = M.definition.group,
    version = M.definition.version,
  }

  commands.run_async("get_single_async", {
    kind = M.definition.gvk.k,
    name = name,
    namespace = ns,
    output = def.syntax,
  }, function(data)
    local builder = manager.get_or_create(def.resource)
    builder.data = data
    builder.decodeJson()
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

      builder.action_view(def, pf_data, function(args)
        local client = require("kubectl.client")
        local address = args[1].value
        local local_port = args[2].value
        local remote_port = args[3].value
        client.portforward_start(M.definition.gvk.k, name, ns, address, local_port, remote_port)
      end)
    end)
  end)
end

function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
