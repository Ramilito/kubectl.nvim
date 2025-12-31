local ansi = require("kubectl.utils.ansi")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local manager = require("kubectl.resource_manager")

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
  "drift",
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

--- Get file/directory completions for a partial path
--- @param partial string The partial path to complete
--- @return string[] completions List of matching paths
local function get_path_completions(partial)
  -- Expand ~ to home directory for completion
  local expanded = vim.fn.expand(partial)

  -- If partial is empty, complete from cwd
  if partial == "" then
    expanded = "./"
  end

  -- Get file completions
  local completions = vim.fn.getcompletion(expanded, "file")

  -- Also add some useful shortcuts at the start
  if partial == "" then
    table.insert(completions, 1, "%") -- Current file
    table.insert(completions, 2, "%:h") -- Current file's directory
  end

  return completions
end

--- User command completion
--- @param _ any Unused parameter
--- @param cmd string The command to complete
--- @return string[]|nil commands The list of top-level commands if applicable
function M.user_command_completion(_, cmd)
  local parts = {}
  for part in string.gmatch(cmd, "%S+") do
    table.insert(parts, part)
  end

  -- Check if we're still typing the command (ends with space = ready for next arg)
  local ends_with_space = cmd:sub(-1) == " "

  if #parts == 1 and not ends_with_space then
    return top_level_commands
  elseif #parts == 1 and ends_with_space then
    -- Just typed "Kubectl ", show subcommands
    return top_level_commands
  elseif parts[2] == "get" then
    if #parts == 2 and ends_with_space then
      local cache = require("kubectl.cache")
      local data = {}
      for _, res in pairs(cache.cached_api_resources.values) do
        table.insert(data, res.name)
      end
      return data
    elseif #parts == 3 and not ends_with_space then
      -- Filtering resources
      local cache = require("kubectl.cache")
      local data = {}
      for _, res in pairs(cache.cached_api_resources.values) do
        table.insert(data, res.name)
      end
      return data
    end
  elseif parts[2] == "top" then
    if #parts == 2 then
      return { "pods", "nodes" }
    end
  elseif parts[2] == "drift" or parts[2] == "diff" then
    -- Path completion for drift/diff commands
    local partial = parts[3] or ""
    if not ends_with_space and #parts == 3 then
      -- User is typing a path, complete it
      return get_path_completions(partial)
    elseif ends_with_space and #parts == 2 then
      -- Just typed "Kubectl drift ", show path completions
      return get_path_completions("")
    end
  end
end

function M.diff(path)
  if path == "." then
    path = vim.fn.expand("%:p")
  end
  local buf = buffers.floating_buffer("k8s_diff", "diff")

  if config.options.diff.bin == "kubediff" then
    local column_size = vim.api.nvim_win_get_width(0)
    local args = { "-t", tostring(column_size) }
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

  local builder = manager.get_or_create("kubectl_apply")

  commands.shell_command_async("kubectl", { "diff", "-f", "-" }, function(data)
    builder.data = data
    builder.splitData()
    vim.schedule(function()
      local win_config
      builder.buf_nr, win_config = buffers.confirmation_buffer("Apply " .. file_name .. "?", "diff", function(confirm)
        if confirm then
          commands.shell_command_async("kubectl", { "apply", "-f", "-" }, nil, nil, nil, { stdin = content })
        end
      end)

      if #builder.data == 1 then
        table.insert(builder.data, "[Info]: No changes found when running diff.")
      end
      local confirmation = "[y]es [n]o:"
      local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

      table.insert(builder.data, padding .. confirmation)
      builder.displayContentRaw()
    end)
  end, nil, nil, { stdin = content })
end

return M
