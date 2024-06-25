local commands = require("kubectl.actions.commands")
local defaults = require("kubectl.config")
local hl = require("kubectl.actions.highlight")

local M = {}
M.context = {}
M.ns = ""
M.filter = ""
M.sortby = ""
M.proxyUrl = ""

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
  local original_win = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]

  vim.api.nvim_open_win(0, true, {
    relative = "win",
    width = original_win.width or vim.o.columns,
    height = original_win.height or vim.o.lines,
    row = original_win.winrow or 0,
    col = original_win.wincol or 0,
    style = "minimal",
  })
  hl.setup()
end

function M.setConfig()
  commands.shell_command_async("kubectl", { "config", "view", "--minify", "-o", "json" }, function(data)
    local pod_view = require("kubectl.views.pods")
    local result = decode(data)
    M.context = result
    M.ns = defaults.options.namespace
    M.filter = ""
    M.sortby = ""

    pod_view.Pods()
  end)
end

function M.getOriginalWin()
  return M.original_win
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

function M.getSortBy()
  return M.sortby
end

function M.setSortBy(pattern)
  M.sortby = pattern
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
