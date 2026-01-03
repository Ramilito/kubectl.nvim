---@class CommandSpec
---@field name string Command name (e.g., "get", "diff")
---@field execute fun(args: string[]) Execute the command
---@field complete? fun(args: string[], parsed: ParsedArgs): string[] Return completions for args
---@field flags? FlagSpec[] Flag specifications for this command

---@class FlagSpec
---@field name string Long flag name (e.g., "namespace")
---@field short? string Short flag (e.g., "n")
---@field takes_value boolean Whether flag expects a value
---@field complete? fun(): string[] Completion for flag values

local parser = require("kubectl.commands.parser")

local M = {
  ---@type table<string, CommandSpec>
  commands = {},
}

---@type string[]
M.top_level_commands = {
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

--- Register a command handler
---@param spec CommandSpec
function M.register(spec)
  M.commands[spec.name] = spec
end

--- Execute a command by name
---@param args string[] Command arguments (first arg is command name)
function M.execute(args)
  if #args == 0 then
    return
  end

  local cmd_name = args[1]
  local cmd = M.commands[cmd_name]

  if cmd then
    local remaining = vim.list_slice(args, 2)
    cmd.execute(remaining)
  else
    -- Fallback to raw kubectl execution
    local view = require("kubectl.views")
    view.UserCmd(args)
  end
end

--- Find a flag spec by long name
---@param flags FlagSpec[]|nil
---@param name string
---@return FlagSpec|nil
local function find_flag(flags, name)
  if not flags then
    return nil
  end
  for _, flag in ipairs(flags) do
    if flag.name == name then
      return flag
    end
  end
  return nil
end

--- Find a flag spec by short name
---@param flags FlagSpec[]|nil
---@param short string
---@return FlagSpec|nil
local function find_flag_by_short(flags, short)
  if not flags then
    return nil
  end
  for _, flag in ipairs(flags) do
    if flag.short == short then
      return flag
    end
  end
  return nil
end

--- Find flag spec for previous argument (handles -n and --namespace)
---@param flags FlagSpec[]|nil
---@param prev string
---@return FlagSpec|nil
local function find_flag_for_prev(flags, prev)
  if not flags then
    return nil
  end
  if prev:match("^%-%-") then
    local name = prev:gsub("^%-%-", "")
    return find_flag(flags, name)
  elseif prev:match("^%-") then
    local short = prev:gsub("^%-", "")
    return find_flag_by_short(flags, short)
  end
  return nil
end

--- Complete flag names based on prefix
---@param flags FlagSpec[]
---@param prefix string
---@return string[]
local function complete_flag_names(flags, prefix)
  local results = {}
  local is_long = prefix:match("^%-%-")

  for _, flag in ipairs(flags) do
    if is_long then
      local candidate = "--" .. flag.name
      if candidate:find(prefix, 1, true) == 1 then
        table.insert(results, candidate)
      end
    else
      if flag.short then
        local candidate = "-" .. flag.short
        if candidate:find(prefix, 1, true) == 1 then
          table.insert(results, candidate)
        end
      end
    end
  end

  return results
end

--- Filter out flags from parts, returning only positional args
---@param parts string[]
---@param flags FlagSpec[]|nil
---@return string[]
local function filter_positional(parts, flags)
  local positional = {}
  local i = 1
  -- Skip "Kubectl" and command name
  local start = 3

  while i <= #parts do
    if i < start then
      i = i + 1
    else
      local arg = parts[i]
      if arg:match("^%-") then
        -- Check if this flag takes a value
        local flag_spec = find_flag_for_prev(flags, arg)
        if flag_spec and flag_spec.takes_value then
          i = i + 1 -- Skip the value too
        end
      else
        table.insert(positional, arg)
      end
      i = i + 1
    end
  end

  return positional
end

--- Complete command arguments
---@param _ string Lead (unused)
---@param cmdline string Full command line
---@return string[]|nil
function M.complete(_, cmdline)
  local parts = {}
  for part in string.gmatch(cmdline, "%S+") do
    table.insert(parts, part)
  end

  -- Handle trailing space (user is asking for next completion)
  local trailing_space = cmdline:match("%s$")
  local last = trailing_space and "" or (parts[#parts] or "")

  -- Level 1: "Kubectl <TAB>" → top_level_commands
  if #parts <= 1 or (#parts == 2 and not trailing_space) then
    return M.top_level_commands
  end

  local cmd_name = parts[2]
  local cmd = M.commands[cmd_name]

  -- Flag name completion: --<TAB> or -<TAB>
  if last:match("^%-") and not trailing_space then
    if cmd and cmd.flags then
      return complete_flag_names(cmd.flags, last)
    end
    return {}
  end

  -- Flag value completion: -n <TAB> or --namespace <TAB>
  if trailing_space and #parts >= 3 then
    local prev = parts[#parts]
    if prev and prev:match("^%-") then
      local flag_spec = find_flag_for_prev(cmd and cmd.flags, prev)
      if flag_spec and flag_spec.takes_value and flag_spec.complete then
        return flag_spec.complete()
      end
    end
  end

  -- Positional argument completion
  if cmd and cmd.complete then
    local positional = filter_positional(parts, cmd and cmd.flags)
    local parsed = parser.parse(vim.list_slice(parts, 3), cmd.flags)
    return cmd.complete(positional, parsed)
  end

  return {}
end

--- Load all command modules to trigger registration
function M.load_commands()
  require("kubectl.commands.get")
  require("kubectl.commands.top")
  require("kubectl.commands.diff")
  require("kubectl.commands.apply")
  require("kubectl.commands.api_resources")
end

return M
