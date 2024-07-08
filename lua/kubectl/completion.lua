local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local kube = require("kubectl.actions.kube")
local M = {}

---@type string[]
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

---@type table<string, string[]>
local views = {
  pods = { "pods", "pod", "po" },
  deployments = { "deployments", "deployment", "deploy" },
  events = { "events", "event", "ev" },
  nodes = { "nodes", "node", "no" },
  secrets = { "secrets", "secret", "sec" },
  services = { "services", "service", "svc" },
  configmaps = { "configmaps", "configmap", "configmaps" },
}

--- User command completion
--- @param _ any Unused parameter
--- @param cmd string The command to complete
--- @return string[]|nil commands The list of top-level commands if applicable
function M.user_command_completion(_, cmd)
  local parts = {}
  for part in string.gmatch(cmd, "%S+") do
    table.insert(parts, part)
  end
  if #parts == 1 then
    return top_level_commands
  end
end

--- Find the view command
--- @param arg string The argument to match with the views
--- @return function|nil view The view function if found, nil otherwise
function M.find_view_command(arg)
  for k, v in pairs(views) do
    if vim.tbl_contains(v, arg) then
      local view = require("kubectl.views." .. k)
      return view.View
    end
  end
  return nil
end

--- Returns a list of context-names
--- @return string[]
function M.list_contexts()
  local contexts = commands.execute_shell_command("kubectl", { "config", "get-contexts", "-o", "name", "--no-headers" })
  return vim.split(contexts, "\n")
end

--- Change context and restart proxy
--- @param cmd string
function M.change_context(cmd)
  local results = commands.shell_command("kubectl", { "config", "use-context", cmd })

  vim.notify(results, vim.log.levels.INFO)
  kube.stop_kubectl_proxy()
  kube.startProxy(function()
    vim.api.nvim_input("R")
  end)
end

function M.diff(cmd)
  local inline_script = "nvim $2"
  -- local inline_script = "echo  $1 $2"

  buffers.floating_buffer({}, {}, "k8s_diff", { title = "diff", syntax = "yaml" })
  local results = commands.execute_terminal(
    "kubectl",
    { "diff", "-f", "./k8s/base/echoserver.yaml" }
    -- { env = { KUBECTL_EXTERNAL_DIFF = inline_script } }
  )
  print(results)
end

return M
