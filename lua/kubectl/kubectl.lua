--- Fugitive-like kubectl command wrapper
--- Runs kubectl commands and displays output in a split buffer
local M = {}

--- kubectl subcommands for completion
local subcommands = {
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
  "view",
  "wait",
}

--- Commands that take a resource type as first arg
local resource_commands = {
  get = true,
  describe = true,
  delete = true,
  edit = true,
  label = true,
  annotate = true,
  patch = true,
  explain = true,
  view = true,
}

--- Commands that take a pod name
local pod_commands = {
  logs = true,
  exec = true,
  attach = true,
  ["port-forward"] = true,
  cp = true,
  debug = true,
}

--- Run kubectl synchronously and return output
---@param args string[]
---@return string[], string|nil  -- lines, error_message
local function kubectl_sync(args)
  local cmd = vim.list_extend({ "kubectl" }, args)
  local result = vim.fn.systemlist(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    local err_msg = table.concat(result, "\n")
    return {}, err_msg ~= "" and err_msg or "Command failed with exit code " .. exit_code
  end

  return result, nil
end

--- Get resource type names for completion
---@return string[]
local function get_resource_types()
  local ok, cache = pcall(require, "kubectl.cache")
  if ok and cache.cached_api_resources and cache.cached_api_resources.values then
    local names = {}
    for _, res in pairs(cache.cached_api_resources.values) do
      if res.name then
        table.insert(names, res.name)
      end
    end
    if #names > 0 then
      return names
    end
  end
  local lines = kubectl_sync({ "api-resources", "-o", "name", "--no-headers" }) or {}
  return lines
end

--- Get resource instance names for completion
---@param resource_type string
---@return string[]
local function get_resource_names(resource_type)
  local lines = kubectl_sync({ "get", resource_type, "-o", "name", "--no-headers" })
  ---@cast lines string[]
  local names = {}
  for _, line in ipairs(lines) do
    local name = line:gsub("^[^/]+/", "")
    if name ~= "" then
      table.insert(names, name)
    end
  end
  return names
end

--- Get namespace names for completion
---@return string[]
local function get_namespaces()
  local lines = kubectl_sync({ "get", "namespaces", "-o", "name", "--no-headers" })
  ---@cast lines string[]
  local names = {}
  for _, line in ipairs(lines) do
    local name = line:gsub("^namespace/", "")
    if name ~= "" then
      table.insert(names, name)
    end
  end
  return names
end

--- Open output in a split buffer
---@param lines string[]
---@param title string
---@param args string[]
local function open_split(lines, title, args)
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_name(buf, title)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  local opts = { buffer = buf, silent = true }

  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, opts)

  vim.keymap.set("n", "R", function()
    local new_output = kubectl_sync(args)
    if #new_output > 0 then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_output)
      vim.bo[buf].modifiable = false
      vim.notify("Refreshed", vim.log.levels.INFO)
    end
  end, opts)

  vim.api.nvim_echo({
    { "kubectl: ", "Title" },
    { "q", "Keyword" },
    { "=close  ", "Comment" },
    { "R", "Keyword" },
    { "=refresh  ", "Comment" },
  }, false, {})
end

--- Execute a kubectl command
---@param args string[]
function M.execute(args)
  if #args == 0 then
    return
  end

  local cmd = args[1]

  -- Special case: "top" opens dashboard
  if cmd == "top" then
    local dashboard = require("kubectl.views.dashboard")
    dashboard.top()
    return
  end

  -- Special case: "api-resources" opens interactive view
  if cmd == "api-resources" and #args == 1 then
    require("kubectl.resources.api-resources").View()
    return
  end

  -- Special case: "view <resource>" opens interactive kubectl.nvim view
  if cmd == "view" and #args >= 2 then
    local kubectl_main = require("kubectl")
    local resource = args[2]

    kubectl_main.init(function(ok)
      if ok then
        require("kubectl.views").resource_or_fallback(resource)
      end
    end)
    return
  end

  -- Run kubectl and show output
  local output, err = kubectl_sync(args)
  if err then
    vim.notify("kubectl error: " .. err, vim.log.levels.ERROR)
    return
  end
  if #output == 0 then
    vim.notify("kubectl: command produced no output", vim.log.levels.INFO)
    return
  end

  local title = "kubectl " .. table.concat(args, " ")
  open_split(output, title, args)
end

--- Filter completions by prefix
---@param items string[]
---@param prefix string
---@return string[]
local function filter_completions(items, prefix)
  if not prefix or prefix == "" then
    return items
  end
  local filtered = {}
  for _, item in ipairs(items) do
    if item:sub(1, #prefix) == prefix then
      table.insert(filtered, item)
    end
  end
  return filtered
end

--- Complete kubectl command arguments
---@param _ string
---@param cmdline string
---@return string[]|nil
function M.complete(_, cmdline)
  local parts = {}
  for part in string.gmatch(cmdline, "%S+") do
    table.insert(parts, part)
  end

  local trailing_space = cmdline:match("%s$")

  -- "Kubectl <TAB>" or "Kubectl g<TAB>" -> subcommands
  if #parts == 1 then
    return subcommands
  end
  if #parts == 2 and not trailing_space then
    return filter_completions(subcommands, parts[2])
  end

  local cmd = parts[2]

  if resource_commands[cmd] then
    -- "Kubectl get <TAB>" -> all resource types
    if #parts == 2 and trailing_space then
      return get_resource_types()
    end
    -- "Kubectl get p<TAB>" -> filtered resource types
    if #parts == 3 and not trailing_space then
      return filter_completions(get_resource_types(), parts[3])
    end
    -- "Kubectl get pods <TAB>" -> all resource names
    if #parts == 3 and trailing_space then
      return get_resource_names(parts[3])
    end
    -- "Kubectl get pods my<TAB>" -> filtered resource names
    if #parts == 4 and not trailing_space then
      return filter_completions(get_resource_names(parts[3]), parts[4])
    end
  end

  if pod_commands[cmd] then
    -- "Kubectl logs <TAB>" -> all pod names
    if #parts == 2 and trailing_space then
      return get_resource_names("pods")
    end
    -- "Kubectl logs my<TAB>" -> filtered pod names
    if #parts == 3 and not trailing_space then
      return filter_completions(get_resource_names("pods"), parts[3])
    end
  end

  if cmd == "top" then
    -- "Kubectl top <TAB>" -> pods/nodes
    if #parts == 2 and trailing_space then
      return { "pods", "nodes" }
    end
    -- "Kubectl top p<TAB>" -> filtered
    if #parts == 3 and not trailing_space then
      return filter_completions({ "pods", "nodes" }, parts[3])
    end
  end

  local last = parts[#parts] or ""
  if last == "-n" or last == "--namespace" then
    if trailing_space then
      return get_namespaces()
    end
  end

  if last:match("^%-") and not trailing_space then
    return filter_completions(
      { "-n", "--namespace", "-o", "--output", "-l", "--selector", "-A", "--all-namespaces" },
      last
    )
  end

  return {}
end

return M
