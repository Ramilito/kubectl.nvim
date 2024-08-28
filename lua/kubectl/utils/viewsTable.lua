-- All main views
---@alias ViewTable table<string, string[]>
---@type ViewTable
return {
  pods = { "pods", "pod", "po" },
  deployments = { "deployments", "deployment", "deploy", "deployments.apps" },
  daemonsets = { "daemonsets", "daemonset", "ds", "daemonsets.apps" },
  jobs = { "jobs", "job", "jo", "jobs.batch" },
  cronjobs = { "cronjobs", "cronjob", "cj", "cronjobs.batch" },
  events = { "events", "event", "ev", "events.events.k8s.io" },
  nodes = { "nodes", "node", "no" },
  sa = { "serviceaccounts", "serviceaccount", "sa" },
  secrets = { "secrets", "secret", "sec" },
  services = { "services", "service", "svc" },
  configmaps = { "configmaps", "configmap", "cm" },
  crds = { "customresourcedefinitions", "crds", "crd", "customresourcedefinitions.apiextensions.k8s.io" },
  pv = { "persistentvolumes", "persistentvolume", "pv" },
  pvc = { "persistentvolumeclaims", "persistentvolumeclaim", "pvc" },
  clusterrolebinding = { "clusterrolebindings", "clusterrolebinding", "clusterrolebindings.rbac.authorization.k8s.io" },
  top = { "top", "top-pods", "top-nodes" },
}
