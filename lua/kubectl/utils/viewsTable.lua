-- All main views
---@alias ViewTable table<string, string[]>
---@type ViewTable
return {
  pods = { "pods", "pod", "po" },
  deployments = { "deployments", "deployment", "deploy", "deployments.apps" },
  daemonsets = { "daemonsets", "daemonset", "ds" },
  events = { "events", "event", "ev" },
  nodes = { "nodes", "node", "no" },
  sa = { "serviceaccounts", "serviceaccount", "sa" },
  secrets = { "secrets", "secret", "sec" },
  services = { "services", "service", "svc" },
  configmaps = { "configmaps", "configmap", "cm" },
  crds = { "customresourcedefinitions", "crds", "crd" },
  pv = { "persistentvolumes", "persistentvolume", "pv" },
  pvc = { "persistentvolumeclaims", "persistentvolumeclaim", "pvc" },
  clusterrolebinding = { "clusterrolebindings", "clusterrolebinding", "clusterrolebindings.rbac.authorization.k8s.io" },
}
