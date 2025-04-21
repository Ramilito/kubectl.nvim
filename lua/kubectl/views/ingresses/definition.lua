local time = require("kubectl.utils.time")

local M = {}

local function get_ports(row)
  if not row or not row.spec or not row.spec.rules then
    return ""
  end
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
  if not row or not row.status or not row.status.loadBalancer or not row.status.loadBalancer.ingress then
    return ""
  end
  local addresses = {}
  for _, ingress in ipairs(row.status.loadBalancer.ingress) do
    if ingress.hostname then
      table.insert(addresses, ingress.hostname)
    elseif ingress.ip then
      table.insert(addresses, ingress.ip)
    end
  end

  return table.concat(addresses, ", ")
end

local function get_class(row)
  local class_name = row.spec and row.spec.ingressClassName
  local class_annotation = row
    and row.metadata
    and row.metadata.annotations
    and row.metadata.annotations["kubernetes.io/ingress.class"]
  return class_name or class_annotation or ""
end

function M.processRow(rows)
  local data = {}

  if not rows then
    return data
  end

  local currentTime = time.currentTime()
  if rows then
    for i = 1, #rows do
      local row = rows[i]
      if row.metadata then
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
  end
  return data
end

return M
