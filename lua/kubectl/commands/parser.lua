---@class ParsedArgs
---@field positional string[] Positional arguments
---@field flags table<string, string|boolean> Parsed flags (name -> value or true)

local M = {}

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

--- Parse command arguments into positional args and flags
---@param args string[] Arguments to parse (excluding command name)
---@param flag_specs FlagSpec[]|nil Flag specifications
---@return ParsedArgs
function M.parse(args, flag_specs)
  ---@type ParsedArgs
  local result = { positional = {}, flags = {} }
  local i = 1

  while i <= #args do
    local arg = args[i]

    if arg:match("^%-%-") then
      -- Long flag: --namespace=foo or --namespace foo
      local name, value = arg:match("^%-%-([^=]+)=?(.*)")
      if name then
        local spec = find_flag(flag_specs, name)
        if spec and spec.takes_value then
          if value and value ~= "" then
            result.flags[name] = value
          elseif args[i + 1] then
            result.flags[name] = args[i + 1]
            i = i + 1
          end
        else
          result.flags[name] = true
        end
      end
    elseif arg:match("^%-") and not arg:match("^%-%-") then
      -- Short flag: -n foo or -A
      local short = arg:sub(2)
      local spec = find_flag_by_short(flag_specs, short)
      if spec then
        if spec.takes_value and args[i + 1] then
          result.flags[spec.name] = args[i + 1]
          i = i + 1
        else
          result.flags[spec.name] = true
        end
      else
        -- Unknown short flag, treat as boolean
        result.flags[short] = true
      end
    else
      table.insert(result.positional, arg)
    end

    i = i + 1
  end

  return result
end

return M
