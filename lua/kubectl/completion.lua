local ansi = require("kubectl.utils.ansi")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local kube = require("kubectl.actions.kube")
local M = {
  contexts = {},
}

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
  elseif #parts == 2 and parts[2] == "get" then
    local view = require("kubectl.views")
    local data = {}
    for _, res in pairs(view.cached_api_resources.values) do
      table.insert(data, res.name)
    end
    return data
  end
end

--- Returns a list of context-names
--- @return string[]
function M.list_contexts()
  if #M.contexts > 0 then
    return M.contexts
  end
  local contexts = commands.shell_command("kubectl", { "config", "get-contexts", "-o", "name", "--no-headers" })
  M.contexts = vim.split(contexts, "\n")
  return M.contexts
end

--- Returns a list of namespaces
--- @return string[]
function M.list_namespaces()
  local output = commands.shell_command("kubectl", { "get", "ns", "-o", "name", "--no-headers" })
  local ns = {}
  for line in output:gmatch("[^\r\n]+") do
    local namespace = line:match("^namespace/(.+)$")
    if namespace then
      table.insert(ns, namespace)
    end
  end
  return ns
end

--- Change context and restart proxy
--- @param cmd string
function M.change_context(cmd)
  local results = commands.shell_command("kubectl", { "config", "use-context", cmd })

  vim.notify(results, vim.log.levels.INFO)
  kube.stop_kubectl_proxy()
  kube.start_kubectl_proxy(function()
    local state = require("kubectl.state")
    state.setup()
  end)
end

function M.diff(path)
  local buf = buffers.floating_buffer("k8s_diff", "diff")

  if config.options.diff.bin == "kubediff" then
    local column_size = vim.api.nvim_win_get_width(0)
    local args = { "-t", column_size }
    if path then
      table.insert(args, "-p")
      table.insert(args, path)
    end
    commands.shell_command_async(config.options.diff.bin, args, function(data)
      local stripped_output = {}

      local content = vim.split(data, "\n")
      for _, line in ipairs(content) do
        local stripped = ansi.strip_ansi_codes(line)
        table.insert(stripped_output, stripped)
      end
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, stripped_output)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        ansi.apply_highlighting(buf, content, stripped_output)
      end)
    end)
  else
    commands.execute_terminal(
      "kubectl",
      { "diff", "-f", path },
      { env = { KUBECTL_EXTERNAL_DIFF = config.options.diff.bin } }
    )
  end
end

function M.apply()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local file_name = vim.api.nvim_buf_get_name(0)
  local content = table.concat(lines, "\n")
  buffers.confirmation_buffer("Apply " .. file_name .. "?", "", function(confirm)
    if confirm then
      commands.shell_command_async("kubectl", { "apply", "-f", "-" }, nil, nil, nil, { stdin = content })
    end
  end)
end

return M
