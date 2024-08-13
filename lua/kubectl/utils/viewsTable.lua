-- All main views
---@alias ViewTable table<string, string[]>
---@type ViewTable
return {
  pods = { "pods", "pod", "po" },
  deployments = { "deployments", "deployment", "deploy" },
  daemonsets = { "daemonsets", "daemonset", "ds" },
  events = { "events", "event", "ev" },
  nodes = { "nodes", "node", "no" },
  secrets = { "secrets", "secret", "sec" },
  services = { "services", "service", "svc" },
  configmaps = { "configmaps", "configmap", "cm" },
  crds = { "customresourcedefinitions", "crds", "crd" },
  pv = { "persistentvolumes", "persistentvolume", "pv" },
  pvc = { "persistentvolumeclaims", "persistentvolumeclaim", "pvc" },
}
