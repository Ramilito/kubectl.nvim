local commands = require("kubectl.actions.commands")
local defaults = require("kubectl.config")

local M = {}
M.context = {}
M.ns = ""
M.filter = ""
M.sortby = ""

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

  M.context = result
  M.ns = defaults.options.namespace
  M.filter = ""
  M.sortby = ""

  return true
end

function M.getContext()
  return M.context
end

function M.getNamespace()
  return M.ns
end

function M.getFilter()
  return M.filter
end

function M.getSortBy()
  return M.sortby
end

function M.setSortBy(pattern)
  M.sortby = pattern
end

function M.setFilter(pattern)
  M.filter = pattern
end

function M.setNS(ns)
  M.ns = ns
end
return M
