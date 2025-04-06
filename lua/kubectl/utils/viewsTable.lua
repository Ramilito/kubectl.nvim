-- All main views
---@alias ViewTable table<string, string[]>
---@type ViewTable
return {
  overview = { "overview" },
  ["api-resources"] = { "api-resources", "apiresources" },
  pods = { "pods", "pod", "po" },
  deployments = { "deployments", "deployment", "deploy", "deployments.apps" },
  replicasets = { "replicasets", "replicaset", "rs", "replicasets.apps" },
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
  contexts = { "contexts", "context" },
  pv = { "persistentvolumes", "persistentvolume", "pv" },
  pvc = { "persistentvolumeclaims", "persistentvolumeclaim", "pvc" },
  clusterrolebindings = { "clusterrolebindings", "clusterrolebinding", "clusterrolebindings.rbac.authorization.k8s.io" },
  ["top_nodes"] = { "top_nodes" },
  ["top_pods"] = { "top_pods" },
  ingresses = { "ingresses", "ingress" },
  helm = { "helm" },
}
