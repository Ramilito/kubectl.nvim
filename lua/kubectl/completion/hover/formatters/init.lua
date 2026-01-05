local M = {}

--- Format labels/annotations as comma-separated string
---@param tbl table|nil
---@param limit number|nil Max items to show
---@return string
local function format_labels(tbl, limit)
  if not tbl or vim.tbl_isempty(tbl) then
    return "_none_"
  end
  limit = limit or 5
  local parts = {}
  local count = 0
  for k, v in pairs(tbl) do
    if count >= limit then
      table.insert(parts, "...")
      break
    end
    table.insert(parts, string.format("`%s=%s`", k, v))
    count = count + 1
  end
  return table.concat(parts, ", ")
end

--- Format age from timestamp
---@param timestamp string|nil
---@return string
local function format_age(timestamp)
  if not timestamp then
    return "unknown"
  end
  local time = require("kubectl.utils.time")
  local result = time.since(timestamp)
  if result and result.value then
    return result.value
  end
  return "unknown"
end

--- Format container status for pods
---@param containers table|nil
---@param statuses table|nil
---@return string
local function format_containers(containers, statuses)
  if not containers or #containers == 0 then
    return "_none_"
  end

  local status_map = {}
  if statuses then
    for _, s in ipairs(statuses) do
      status_map[s.name] = s
    end
  end

  local lines = {}
  for _, c in ipairs(containers) do
    local status = status_map[c.name]
    local state_str = "unknown"
    local icon = "○"

    if status and status.state then
      if status.state.running then
        state_str = "running"
        icon = "●"
      elseif status.state.waiting then
        state_str = status.state.waiting.reason or "waiting"
        icon = "◌"
      elseif status.state.terminated then
        state_str = status.state.terminated.reason or "terminated"
        icon = "○"
      end
    end

    local restarts = status and status.restartCount or 0
    local restart_str = restarts > 0 and string.format(" (%d restarts)", restarts) or ""
    table.insert(lines, string.format("  %s `%s` - %s%s", icon, c.name, state_str, restart_str))
  end
  return table.concat(lines, "\n")
end

--- Format conditions table
---@param conditions table|nil
---@return string
local function format_conditions(conditions)
  if not conditions or #conditions == 0 then
    return "_none_"
  end

  local lines = {}
  for _, c in ipairs(conditions) do
    local icon = c.status == "True" and "✓" or "✗"
    table.insert(lines, string.format("  %s %s", icon, c.type))
  end
  return table.concat(lines, "\n")
end

--- Format Pod resource
---@param data table
---@return string
function M.format_pod(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local lines = {
    string.format("## Pod: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Status:** %s", status.phase or "Unknown"),
    string.format("**Node:** %s", spec.nodeName or "_unscheduled_"),
    string.format("**IP:** %s", status.podIP or "_none_"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Containers",
    format_containers(spec.containers, status.containerStatuses),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format Deployment resource
---@param data table
---@return string
function M.format_deployment(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local replicas = status.replicas or 0
  local ready = status.readyReplicas or 0
  local available = status.availableReplicas or 0

  local lines = {
    string.format("## Deployment: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Replicas:** %d/%d ready, %d available", ready, replicas, available),
    string.format("**Strategy:** %s", spec.strategy and spec.strategy.type or "RollingUpdate"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Conditions",
    format_conditions(status.conditions),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format Service resource
---@param data table
---@return string
function M.format_service(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}

  local ports = {}
  if spec.ports then
    for _, p in ipairs(spec.ports) do
      local port_str = p.targetPort and string.format("%d→%s", p.port, p.targetPort) or tostring(p.port)
      table.insert(ports, string.format("`%s/%s`", port_str, p.protocol or "TCP"))
    end
  end

  local lines = {
    string.format("## Service: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Type:** %s", spec.type or "ClusterIP"),
    string.format("**ClusterIP:** %s", spec.clusterIP or "_none_"),
    string.format("**Ports:** %s", #ports > 0 and table.concat(ports, ", ") or "_none_"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Selector",
    format_labels(spec.selector),
  }

  return table.concat(lines, "\n")
end

--- Format ConfigMap resource
---@param data table
---@return string
function M.format_configmap(data)
  local meta = data.metadata or {}
  local data_keys = data.data and vim.tbl_keys(data.data) or {}

  local lines = {
    string.format("## ConfigMap: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Keys:** %d", #data_keys),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Data Keys",
  }

  if #data_keys > 0 then
    for i, key in ipairs(data_keys) do
      if i > 10 then
        table.insert(lines, string.format("  ... and %d more", #data_keys - 10))
        break
      end
      table.insert(lines, string.format("  - `%s`", key))
    end
  else
    table.insert(lines, "  _empty_")
  end

  return table.concat(lines, "\n")
end

--- Format Secret resource
---@param data table
---@return string
function M.format_secret(data)
  local meta = data.metadata or {}
  local data_keys = data.data and vim.tbl_keys(data.data) or {}

  local lines = {
    string.format("## Secret: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Type:** %s", data.type or "Opaque"),
    string.format("**Keys:** %d", #data_keys),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Data Keys",
  }

  if #data_keys > 0 then
    for i, key in ipairs(data_keys) do
      if i > 10 then
        table.insert(lines, string.format("  ... and %d more", #data_keys - 10))
        break
      end
      table.insert(lines, string.format("  - `%s`", key))
    end
  else
    table.insert(lines, "  _empty_")
  end

  return table.concat(lines, "\n")
end

--- Format Node resource
---@param data table
---@return string
function M.format_node(data)
  local meta = data.metadata or {}
  local status = data.status or {}
  local spec = data.spec or {}

  local addresses = {}
  if status.addresses then
    for _, addr in ipairs(status.addresses) do
      if addr.type == "InternalIP" or addr.type == "ExternalIP" then
        table.insert(addresses, string.format("%s: %s", addr.type, addr.address))
      end
    end
  end

  local lines = {
    string.format("## Node: %s", meta.name or "unknown"),
    "",
    string.format("**Unschedulable:** %s", spec.unschedulable and "yes" or "no"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Addresses",
  }

  if #addresses > 0 then
    for _, addr in ipairs(addresses) do
      table.insert(lines, string.format("  - %s", addr))
    end
  else
    table.insert(lines, "  _none_")
  end

  table.insert(lines, "")
  table.insert(lines, "### Conditions")
  table.insert(lines, format_conditions(status.conditions))

  return table.concat(lines, "\n")
end

--- Generic formatter for any resource
---@param data table
---@return string
function M.format_generic(data)
  local meta = data.metadata or {}
  local status = data.status or {}
  local kind = data.kind or "Resource"

  local lines = {
    string.format("## %s: %s", kind, meta.name or "unknown"),
    "",
  }

  if meta.namespace then
    table.insert(lines, string.format("**Namespace:** %s", meta.namespace))
  end

  table.insert(lines, string.format("**Age:** %s", format_age(meta.creationTimestamp)))

  -- Add conditions if present
  if status.conditions and #status.conditions > 0 then
    table.insert(lines, "")
    table.insert(lines, "### Conditions")
    table.insert(lines, format_conditions(status.conditions))
  end

  table.insert(lines, "")
  table.insert(lines, "### Labels")
  table.insert(lines, format_labels(meta.labels))

  return table.concat(lines, "\n")
end

--- Formatter dispatch table
local formatters = {
  Pod = M.format_pod,
  Deployment = M.format_deployment,
  Service = M.format_service,
  ConfigMap = M.format_configmap,
  Secret = M.format_secret,
  Node = M.format_node,
}

--- Format resource data based on kind
---@param data table Decoded resource JSON
---@param kind string Resource kind
---@return string Markdown formatted content
function M.format(data, kind)
  local formatter = formatters[kind]
  if formatter then
    return formatter(data)
  end
  return M.format_generic(data)
end

return M
