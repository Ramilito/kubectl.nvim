local commands = require("kubectl.actions.commands")
local defaults = require("kubectl.config")

local M = {}
local context = {}
local ns = ""
local filter = ""
local sortby = ""

function M.setup()
  local result = vim.json.decode(commands.execute_shell_command("kubectl", {
    "config",
    "view",
    "--minify",
    "-o",
    "json",
  }))

  context = result
  ns = defaults.options.namespace
  filter = ""
  sortby = ""
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
