local time = require("kubectl.utils.time")

local M = {
  resource = "ingresses",
  display_name = "Ingresses",
  ft = "k8s_ingresses",
  url = { "{{BASE}}/apis/networking.k8s.io/v1/{{NAMESPACE}}ingresses?pretty=false" },
}

local function get_ports(row)
  local ports = {}

  for _, rule in ipairs(row.spec.rules) do
    for _, path in ipairs(rule.http.paths) do
      if path.backend.service and path.backend.service.port then
        local port = path.backend.service.port and path.backend.service.port.number or "80"
        ports[port] = true
      end
    end
  end

  if row.spec.tls then
    ports["443"] = true
  end

  return table.concat(vim.tbl_keys(ports), ", ")
end

local function get_hosts(row)
  if not row.spec or not row.spec.rules then
    return ""
  end
  local hosts = {}

  for _, rule in ipairs(row.spec.rules) do
    table.insert(hosts, rule.host)
  end
  local total_hosts = #hosts
  if total_hosts > 4 then
    return table.concat(hosts, ", ", 1, 4) .. ", +" .. (total_hosts - 4) .. " more..."
  else
    return table.concat(hosts, ", ")
  end
end

local function get_address(row)
  local addresses = {}
  if row.status and row.status.loadBalancer and row.status.loadBalancer.ingress then
    for _, ingress in ipairs(row.status.loadBalancer.ingress) do
      if ingress.hostname then
        table.insert(addresses, ingress.hostname)
      elseif ingress.ip then
        table.insert(addresses, ingress.ip)
      end
    end
  end

  return table.concat(addresses, ", ")
end

local function get_class(row)
  return row.spec.ingressClassName
    or row.metadata.annotations and row.metadata.annotations["kubernetes.io/ingress.class"]
    or ""
end

function M.processRow(rows)
  local data = {}

  if not rows or not rows.items then
    return data
  end

  local currentTime = time.currentTime()
  if rows and rows.items then
    for i = 1, #rows.items do
      local row = rows.items[i]
      data[i] = {
        namespace = row.metadata.namespace,
        name = row.metadata.name,
        class = get_class(row),
        hosts = get_hosts(row),
        address = get_address(row),
        ports = get_ports(row),
        age = time.since(row.metadata.creationTimestamp, true, currentTime),
      }
    end
  end
  return data
end

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "CLASS",
    "HOSTS",
    "ADDRESS",
    "PORTS",
    "AGE",
  }

  return headers
end

return M
