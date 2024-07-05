local M = {}
M.context = {}
M.ns = ""
M.filter = ""
M.proxyUrl = ""
M.notifications = {}
M.marks = { ns_id = 0, header = {} }
M.sortby = { mark = {}, current_word = "" }

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
  local commands = require("kubectl.actions.commands")
  local config = require("kubectl.config")

  commands.shell_command_async("kubectl", { "config", "view", "--minify", "-o", "json" }, function(data)
    local pod_view = require("kubectl.views.pods")
    local result = decode(data)
    M.context = result
    M.ns = config.options.namespace
    M.filter = ""

    pod_view.View()
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

function M.getProxyUrl()
  return M.proxyUrl
end

function M.setFilter(pattern)
  M.filter = pattern
end

function M.setProxyUrl(port)
  M.proxyUrl = "http://127.0.0.1:" .. port
end

function M.setNS(ns)
  M.ns = ns
end

return M
