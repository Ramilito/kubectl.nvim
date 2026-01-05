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
    local ready = false

    if status and status.state then
      ready = status.ready or false
      if status.state.running then
        state_str = "running"
        icon = ready and "●" or "◐"
      elseif status.state.waiting then
        state_str = status.state.waiting.reason or "waiting"
        icon = "◌"
      elseif status.state.terminated then
        state_str = status.state.terminated.reason or "terminated"
        icon = "○"
      end
    end

    local ready_str = ready and "ready" or "not ready"
    local restarts = status and status.restartCount or 0
    local restart_str = restarts > 0 and string.format(", %d restarts", restarts) or ""
    table.insert(lines, string.format("  %s `%s` - %s (%s%s)", icon, c.name, state_str, ready_str, restart_str))
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
    "### Conditions",
    format_conditions(status.conditions),
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

--- Format StatefulSet resource
---@param data table
---@return string
function M.format_statefulset(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local replicas = status.replicas or 0
  local ready = status.readyReplicas or 0
  local current = status.currentReplicas or 0

  local lines = {
    string.format("## StatefulSet: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Replicas:** %d/%d ready, %d current", ready, replicas, current),
    string.format("**Service:** %s", spec.serviceName or "_none_"),
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

--- Format DaemonSet resource
---@param data table
---@return string
function M.format_daemonset(data)
  local meta = data.metadata or {}
  local status = data.status or {}

  local desired = status.desiredNumberScheduled or 0
  local current = status.currentNumberScheduled or 0
  local ready = status.numberReady or 0
  local available = status.numberAvailable or 0

  local lines = {
    string.format("## DaemonSet: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Desired:** %d", desired),
    string.format("**Current:** %d", current),
    string.format("**Ready:** %d", ready),
    string.format("**Available:** %d", available),
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

--- Format ReplicaSet resource
---@param data table
---@return string
function M.format_replicaset(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local ready = status.readyReplicas or 0
  local available = status.availableReplicas or 0

  local owner_str = "_none_"
  if meta.ownerReferences and #meta.ownerReferences > 0 then
    local owner = meta.ownerReferences[1]
    owner_str = string.format("`%s/%s`", owner.kind, owner.name)
  end

  local lines = {
    string.format("## ReplicaSet: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Replicas:** %d/%d ready, %d available", ready, spec.replicas or 0, available),
    string.format("**Owner:** %s", owner_str),
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

--- Format Job resource
---@param data table
---@return string
function M.format_job(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local completions = spec.completions or 1
  local succeeded = status.succeeded or 0
  local failed = status.failed or 0
  local active = status.active or 0

  local duration = "_running_"
  if status.completionTime and status.startTime then
    local time = require("kubectl.utils.time")
    duration = time.since(status.startTime).value or "unknown"
  end

  local lines = {
    string.format("## Job: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Completions:** %d/%d", succeeded, completions),
    string.format("**Active:** %d", active),
    string.format("**Failed:** %d", failed),
    string.format("**Duration:** %s", duration),
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

--- Format CronJob resource
---@param data table
---@return string
function M.format_cronjob(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local last_schedule = status.lastScheduleTime and format_age(status.lastScheduleTime) or "_never_"
  local active_count = status.active and #status.active or 0

  local lines = {
    string.format("## CronJob: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Schedule:** `%s`", spec.schedule or "_none_"),
    string.format("**Suspend:** %s", spec.suspend and "yes" or "no"),
    string.format("**Active Jobs:** %d", active_count),
    string.format("**Last Schedule:** %s ago", last_schedule),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format Ingress resource
---@param data table
---@return string
function M.format_ingress(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  -- Collect hosts
  local hosts = {}
  if spec.rules then
    for _, rule in ipairs(spec.rules) do
      if rule.host then
        table.insert(hosts, string.format("`%s`", rule.host))
      end
    end
  end

  -- Get load balancer IPs
  local lb_ips = {}
  if status.loadBalancer and status.loadBalancer.ingress then
    for _, ing in ipairs(status.loadBalancer.ingress) do
      table.insert(lb_ips, ing.ip or ing.hostname or "pending")
    end
  end

  local lines = {
    string.format("## Ingress: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Class:** %s", spec.ingressClassName or "_default_"),
    string.format("**Hosts:** %s", #hosts > 0 and table.concat(hosts, ", ") or "_none_"),
    string.format("**Address:** %s", #lb_ips > 0 and table.concat(lb_ips, ", ") or "_pending_"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format PersistentVolumeClaim resource
---@param data table
---@return string
function M.format_pvc(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local capacity = status.capacity and status.capacity.storage or "_unknown_"
  local access_modes = spec.accessModes and table.concat(spec.accessModes, ", ") or "_none_"

  local lines = {
    string.format("## PersistentVolumeClaim: %s", meta.name or "unknown"),
    "",
    string.format("**Namespace:** %s", meta.namespace or "default"),
    string.format("**Status:** %s", status.phase or "Unknown"),
    string.format("**Volume:** %s", spec.volumeName or "_pending_"),
    string.format("**Capacity:** %s", capacity),
    string.format("**Access Modes:** %s", access_modes),
    string.format("**Storage Class:** %s", spec.storageClassName or "_default_"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format PersistentVolume resource
---@param data table
---@return string
function M.format_pv(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
  local status = data.status or {}

  local capacity = spec.capacity and spec.capacity.storage or "_unknown_"
  local access_modes = spec.accessModes and table.concat(spec.accessModes, ", ") or "_none_"
  local claim = "_none_"
  if spec.claimRef then
    claim = string.format("`%s/%s`", spec.claimRef.namespace or "", spec.claimRef.name or "")
  end

  local lines = {
    string.format("## PersistentVolume: %s", meta.name or "unknown"),
    "",
    string.format("**Status:** %s", status.phase or "Unknown"),
    string.format("**Claim:** %s", claim),
    string.format("**Capacity:** %s", capacity),
    string.format("**Access Modes:** %s", access_modes),
    string.format("**Reclaim Policy:** %s", spec.persistentVolumeReclaimPolicy or "_unknown_"),
    string.format("**Storage Class:** %s", spec.storageClassName or "_none_"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format Namespace resource
---@param data table
---@return string
function M.format_namespace(data)
  local meta = data.metadata or {}
  local status = data.status or {}

  local lines = {
    string.format("## Namespace: %s", meta.name or "unknown"),
    "",
    string.format("**Status:** %s", status.phase or "Unknown"),
    string.format("**Age:** %s", format_age(meta.creationTimestamp)),
    "",
    "### Labels",
    format_labels(meta.labels),
  }

  return table.concat(lines, "\n")
end

--- Format owner references
---@param owners table|nil
---@return string
local function format_owners(owners)
  if not owners or #owners == 0 then
    return "_none_"
  end
  local parts = {}
  for _, owner in ipairs(owners) do
    table.insert(parts, string.format("`%s/%s`", owner.kind, owner.name))
  end
  return table.concat(parts, ", ")
end

--- Format common status fields (replicas, ready, available, etc.)
---@param status table
---@return table lines
local function format_status_fields(status)
  local lines = {}
  local fields = {
    { key = "replicas", label = "Replicas" },
    { key = "readyReplicas", label = "Ready" },
    { key = "availableReplicas", label = "Available" },
    { key = "updatedReplicas", label = "Updated" },
    { key = "currentReplicas", label = "Current" },
    { key = "phase", label = "Phase" },
    { key = "reason", label = "Reason" },
  }

  for _, field in ipairs(fields) do
    if status[field.key] ~= nil then
      table.insert(lines, string.format("**%s:** %s", field.label, tostring(status[field.key])))
    end
  end

  return lines
end

--- Generic formatter for any resource
---@param data table
---@return string
function M.format_generic(data)
  local meta = data.metadata or {}
  local spec = data.spec or {}
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

  -- Add common status fields
  local status_lines = format_status_fields(status)
  for _, line in ipairs(status_lines) do
    table.insert(lines, line)
  end

  -- Show replicas from spec if not in status
  if spec.replicas and not status.replicas then
    table.insert(lines, string.format("**Desired Replicas:** %s", spec.replicas))
  end

  -- Owner references
  if meta.ownerReferences and #meta.ownerReferences > 0 then
    table.insert(lines, string.format("**Owner:** %s", format_owners(meta.ownerReferences)))
  end

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
  StatefulSet = M.format_statefulset,
  DaemonSet = M.format_daemonset,
  ReplicaSet = M.format_replicaset,
  Job = M.format_job,
  CronJob = M.format_cronjob,
  Service = M.format_service,
  Ingress = M.format_ingress,
  ConfigMap = M.format_configmap,
  Secret = M.format_secret,
  PersistentVolumeClaim = M.format_pvc,
  PersistentVolume = M.format_pv,
  Node = M.format_node,
  Namespace = M.format_namespace,
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
