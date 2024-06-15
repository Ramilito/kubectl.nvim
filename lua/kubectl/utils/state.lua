local commands = require("kubectl.actions.commands")
local defaults = require("kubectl.config")
local kube = require("kubectl.utils.kube")

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
    vim.schedule(function()
      vim.notify("Error: current-context unavailable", vim.log.levels.ERROR)
    end)
  end
end

function M.setup()
  commands.shell_command_async("kubectl", { "config", "view", "--minify", "-o", "json" }, function(data)
    local result = decode(data)
    M.context = result
    M.ns = defaults.options.namespace
    M.filter = ""
    M.sortby = ""
  end)
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

function M.startProxy()
  local jobId = kube.startProxy()
  -- commands.shell_command_async("kubectl", { "proxy", "--port=8080" })
end
return M
