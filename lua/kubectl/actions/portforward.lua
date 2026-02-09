local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local tables = require("kubectl.utils.tables")

local M = {}

--- Extract ports from pod spec
---@param spec table Pod spec
---@return table ports List of { name, port, protocol }
local function extract_pod_ports(spec)
  local ports = {}
  for _, container in ipairs(spec.containers or {}) do
    if container.ports then
      for _, port in ipairs(container.ports) do
        local name
        if port.name and container.name then
          name = container.name .. "::(" .. port.name .. ")"
        elseif container.name then
          name = container.name
        else
          name = nil
        end

        table.insert(ports, {
          name = { value = name, symbol = hl.symbols.pending },
          port = { value = port.containerPort, symbol = hl.symbols.success },
          protocol = port.protocol,
        })
      end
    end
  end
  return ports
end

--- Extract ports from service spec
---@param spec table Service spec
---@return table ports List of { name, port, protocol }
local function extract_service_ports(spec)
  local ports = {}
  for _, port in ipairs(spec.ports or {}) do
    local container_port = port.targetPort or port.port
    table.insert(ports, {
      name = { value = port.name, symbol = hl.symbols.pending },
      port = { value = container_port, symbol = hl.symbols.success },
      protocol = port.protocol,
    })
  end
  return ports
end

local port_extractors = {
  pod = extract_pod_ports,
  service = extract_service_ports,
}

--- Port forward action for pods and services
---@param resource_type string "pod" | "service"
---@param gvk table The GVK for the resource
---@param name string Resource name
---@param ns string Resource namespace
function M.portforward(resource_type, gvk, name, ns)
  local resource_key = resource_type == "pod" and "pod_pf" or "svc_pf"
  local def = {
    resource = resource_key,
    display = "PF: " .. name .. "-" .. "?",
    ft = "k8s_action",
    ns = ns,
  }

  commands.run_async("get_single_async", {
    gvk = gvk,
    name = name,
    namespace = ns,
    output = def.syntax,
  }, function(data)
    local builder = manager.get_or_create(def.resource)
    builder.data = data
    builder.decodeJson()

    local extractor = port_extractors[resource_type]
    local ports = extractor(builder.data.spec)

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
          hl = hl.symbols.pending,
        },
        {
          text = "local:",
          value = tostring(ports[1].port.value),
          cmd = "",
          type = "positional",
          hl = hl.symbols.pending,
        },
        {
          text = "container port:",
          value = tostring(ports[1].port.value),
          cmd = ":",
          type = "merge_above",
          hl = hl.symbols.pending,
        },
      }

      builder.action_view(def, pf_data, function(args)
        local client = require("kubectl.client")
        local address = args[1].value
        local local_port = args[2].value
        local remote_port = args[3].value
        client.portforward_start(gvk.k, name, ns, address, local_port, remote_port)
      end)
    end)
  end)
end

return M
