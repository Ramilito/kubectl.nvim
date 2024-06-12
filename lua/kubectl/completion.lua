local deployment_view = require("kubectl.views.deployments")
local events_view = require("kubectl.views.events")
local nodes_view = require("kubectl.views.nodes")
local secrets_view = require("kubectl.views.secrets")
local services_view = require("kubectl.views.services")
local pod_view = require("kubectl.views.pods")
local configmaps_view = require("kubectl.views.configmaps")

local M = {}
local top_level_commands = {
  "annotate",
  "api-resources",
  "api-versions",
  "apply",
  "attach",
  "auth",
  "autoscale",
  "certificate",
  "cluster-info",
  "completion",
  "config",
  "cordon",
  "cp",
  "create",
  "debug",
  "delete",
  "describe",
  "diff",
  "drain",
  "edit",
  "events",
  "exec",
  "explain",
  "expose",
  "get",
  "help",
  "kustomize",
  "label",
  "logs",
  "options",
  "patch",
  "port-forward",
  "proxy",
  "replace",
  "rollout",
  "run",
  "scale",
  "set",
  "taint",
  "top",
  "uncordon",
  "version",
  "wait",
}

local views = {
  pods = { "pods", "pod", "po", pod_view.Pods },
  deployments = { "deployments", "deployment", "deploy", deployment_view.Deployments },
  events = { "events", "event", "ev", events_view.Events },
  nodes = { "nodes", "node", "no", nodes_view.Nodes },
  secrets = { "secrets", "secret", "sec", secrets_view.Secrets },
  services = { "services", "service", "svc", services_view.Services },
  configmaps = { "configmaps", "configmap", "configmaps", configmaps_view.Configmaps },
}

function M.user_command_completion(_, cmd)
  local parts = {}
  for part in string.gmatch(cmd, "%S+") do
    table.insert(parts, part)
  end
  if #parts == 1 then
    return top_level_commands
  end
end

function M.find_view_command(arg)
  for _, v in pairs(views) do
    if vim.tbl_contains(v, arg) then
      return v[#v]
    end
  end
  return nil
end

return M
