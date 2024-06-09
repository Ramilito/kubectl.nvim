local commands = require("kubectl.actions.commands")
local defaults = require("kubectl.config")

local M = {}
local context = {}
local ns = ""
local filter = ""
local sortby = ""

local decode = function(string)
  local success, result = pcall(vim.json.decode, string)
  if success then
    return result
  else
    vim.notify("Error: current-context unavailable", vim.log.levels.ERROR)
  end
end

function M.setup()
  local result = decode(commands.execute_shell_command("kubectl", {
    "config",
    "view",
    "--minify",
    "-o",
    "json",
  }))

  if not result then
    return false
  end

  context = result
  ns = defaults.options.namespace
  filter = ""
  sortby = ""

  return true
end

function M.getContext()
  return context
end

function M.getNamespace()
  return ns
end

function M.getFilter()
  return filter
end

function M.getSortBy()
  return sortby
end

function M.setSortBy(pattern)
  sortby = pattern
end
function M.setFilter(pattern)
  filter = pattern
end

return M
